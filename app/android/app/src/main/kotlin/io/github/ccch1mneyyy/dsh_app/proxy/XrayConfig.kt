package io.github.ccch1mneyyy.dsh_app.proxy

import org.json.JSONArray
import org.json.JSONObject

/**
 * 设置 › 代理: one VLESS + REALITY server, typed in by hand (the fields v2rayNG shows for
 * it). The bundled core is the trimmed Xray (runtime/xray): VLESS + REALITY over RAW
 * (TCP, optionally with Vision flow) or XHTTP, nothing else.
 *
 * Plain Kotlin and org.json only, so the JVM unit tests can build and check it.
 */
data class ProxyConfig(
    val enabled: Boolean = false,
    val address: String = "",
    val port: Int = 443,
    val id: String = "",
    val encryption: String = "none",
    val flow: String = FLOW_VISION,
    /** [NETWORK_RAW] (TCP) or [NETWORK_XHTTP]. */
    val network: String = NETWORK_RAW,
    val sni: String = "",
    val fingerprint: String = "chrome",
    val publicKey: String = "",
    val shortId: String = "",
    val spiderX: String = "",
    val mldsa65Verify: String = "",
    val xhttpHost: String = "",
    val xhttpPath: String = "/",
    val xhttpMode: String = "auto",
) {
    fun toJson(): JSONObject = JSONObject()
        .put("enabled", enabled)
        .put("address", address)
        .put("port", port)
        .put("id", id)
        .put("encryption", encryption)
        .put("flow", flow)
        .put("network", network)
        .put("sni", sni)
        .put("fingerprint", fingerprint)
        .put("publicKey", publicKey)
        .put("shortId", shortId)
        .put("spiderX", spiderX)
        .put("mldsa65Verify", mldsa65Verify)
        .put("xhttpHost", xhttpHost)
        .put("xhttpPath", xhttpPath)
        .put("xhttpMode", xhttpMode)

    /** The first problem as a stable code the app turns into words, or null when usable. */
    fun problem(): String? = when {
        address.isBlank() -> "address"
        port !in 1..65535 -> "port"
        id.isBlank() -> "id"
        network != NETWORK_RAW && network != NETWORK_XHTTP -> "network"
        flow.isNotEmpty() && flow != FLOW_VISION -> "flow"
        publicKey.isBlank() -> "publicKey"
        network == NETWORK_XHTTP && xhttpMode !in XHTTP_MODES -> "xhttpMode"
        else -> null
    }

    /**
     * The Xray configuration: an HTTP proxy on 127.0.0.1:[localPort] that sends everything
     * to the server. [dns] resolve the server's own name inside Xray (the core's Go
     * resolver has no system resolv.conf on Android); destinations go to the server by name.
     */
    fun xray(localPort: Int, dns: List<String>): JSONObject {
        val vless = JSONObject()
            .put("address", address.trim())
            .put("port", port)
            .put("id", id.trim())
            .put("encryption", encryption.trim().ifEmpty { "none" })
        // Vision is a RAW-only flow.
        if (network == NETWORK_RAW && flow.isNotEmpty()) vless.put("flow", flow)
        val reality = JSONObject()
            .put("serverName", sni.trim())
            .put("fingerprint", fingerprint.trim().ifEmpty { "chrome" })
            .put("publicKey", publicKey.trim())
            .put("shortId", shortId.trim())
        if (spiderX.isNotBlank()) reality.put("spiderX", spiderX.trim())
        if (mldsa65Verify.isNotBlank()) reality.put("mldsa65Verify", mldsa65Verify.trim())
        val stream = JSONObject()
            .put("network", network)
            .put("security", "reality")
            .put("realitySettings", reality)
            .put("sockopt", JSONObject().put("domainStrategy", "UseIP"))
        if (network == NETWORK_XHTTP) {
            val xhttp = JSONObject()
                .put("path", xhttpPath.trim().ifEmpty { "/" })
                .put("mode", xhttpMode)
            if (xhttpHost.isNotBlank()) xhttp.put("host", xhttpHost.trim())
            stream.put("xhttpSettings", xhttp)
        }
        return JSONObject()
            .put("log", JSONObject().put("loglevel", "warning"))
            .put("dns", JSONObject().put("servers", JSONArray(dns)))
            .put(
                "inbounds",
                JSONArray().put(
                    JSONObject().put("tag", "http").put("listen", LOOPBACK).put("port", localPort).put("protocol", "http"),
                ),
            )
            .put(
                "outbounds",
                JSONArray().put(
                    JSONObject().put("tag", "proxy").put("protocol", "vless").put("settings", vless).put("streamSettings", stream),
                ),
            )
    }

    companion object {
        const val LOOPBACK = "127.0.0.1"
        const val NETWORK_RAW = "raw"
        const val NETWORK_XHTTP = "xhttp"
        const val FLOW_VISION = "xtls-rprx-vision"
        val XHTTP_MODES = listOf("auto", "packet-up", "stream-up", "stream-one")

        /** Public resolvers for the server's name when the phone reports none. */
        val FALLBACK_DNS = listOf("223.5.5.5", "119.29.29.29")

        fun fromJson(json: JSONObject?): ProxyConfig {
            if (json == null) return ProxyConfig()
            val d = ProxyConfig()
            return ProxyConfig(
                enabled = json.optBoolean("enabled", d.enabled),
                address = json.optString("address", d.address),
                port = json.optInt("port", d.port),
                id = json.optString("id", d.id),
                encryption = json.optString("encryption", d.encryption),
                flow = json.optString("flow", d.flow),
                network = json.optString("network", d.network),
                sni = json.optString("sni", d.sni),
                fingerprint = json.optString("fingerprint", d.fingerprint),
                publicKey = json.optString("publicKey", d.publicKey),
                shortId = json.optString("shortId", d.shortId),
                spiderX = json.optString("spiderX", d.spiderX),
                mldsa65Verify = json.optString("mldsa65Verify", d.mldsa65Verify),
                xhttpHost = json.optString("xhttpHost", d.xhttpHost),
                xhttpPath = json.optString("xhttpPath", d.xhttpPath),
                xhttpMode = json.optString("xhttpMode", d.xhttpMode),
            )
        }

        /**
         * What the engine gets while the proxy runs: Node 24's own proxy support
         * (NODE_USE_ENV_PROXY) for DSH's model requests, and the usual names for the
         * tools it runs. Loopback stays direct: the app talks to the engine there.
         */
        fun engineEnv(localPort: Int): Map<String, String> {
            val url = "http://$LOOPBACK:$localPort"
            val direct = "localhost,127.0.0.1,::1"
            return linkedMapOf(
                "NODE_USE_ENV_PROXY" to "1",
                "HTTP_PROXY" to url,
                "HTTPS_PROXY" to url,
                "NO_PROXY" to direct,
                "http_proxy" to url,
                "https_proxy" to url,
                "no_proxy" to direct,
            )
        }
    }
}
