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
     * The Xray configuration: an HTTP proxy that sends everything to the server. It listens
     * on the abstract Unix socket [socket] only (no TCP port another app could find or
     * use) and asks for [auth]. [dns] resolve the server's own name inside Xray (the
     * core's Go resolver has no system resolv.conf on Android); destinations go to the
     * server by name.
     */
    fun xray(socket: String, auth: Pair<String, String>, dns: List<String>): JSONObject {
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
                    JSONObject().put("tag", "http").put("listen", "@$socket").put("port", 0).put("protocol", "http")
                        .put("settings", JSONObject().put("accounts", JSONArray().put(JSONObject().put("user", auth.first).put("pass", auth.second)))),
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

        /** Env names the engine's preload reads, then removes from its own environment. */
        const val ENV_PORT = "AGENTELLO_NET_PORT"
        const val ENV_SOCKET = "AGENTELLO_NET_SOCKET"
        private val PROXY_NAMES = listOf("HTTP_PROXY", "HTTPS_PROXY", "NO_PROXY", "http_proxy", "https_proxy", "no_proxy")

        /**
         * Runs first in every Node process of the engine (NODE_OPTIONS --import, inline so no
         * path differs between launch methods): connections to the made-up loopback [ENV_PORT]
         * go to the core's abstract socket instead, and once Node has read its proxy settings
         * they leave the environment, so the commands the agent runs (curl, git, pip) never
         * see a proxy that only Node can reach.
         */
        val PRELOAD = """
            import net from 'node:net'
            import 'node:http'
            import 'node:https'
            const port = Number(process.env.$ENV_PORT), path = '\0' + process.env.$ENV_SOCKET
            for (const k of [${(PROXY_NAMES + listOf("NODE_USE_ENV_PROXY", ENV_PORT, ENV_SOCKET)).joinToString(", ") { "'$it'" }}]) delete process.env[k]
            const loopback = new Set([undefined, 'localhost', '127.0.0.1', '::1'])
            const redirect = (o) => {
              if (!o || typeof o !== 'object' || Number(o.port) !== port || !loopback.has(o.host) || o.path) return o
              const { port: _p, host: _h, family: _f, localAddress: _l, localPort: _lp, autoSelectFamily: _a, autoSelectFamilyAttemptTimeout: _t, ...rest } = o
              return { ...rest, path }
            }
            const connect = net.Socket.prototype.connect
            net.Socket.prototype.connect = function (...args) {
              if (Array.isArray(args[0])) args[0][0] = redirect(args[0][0])
              else args[0] = redirect(args[0])
              return connect.apply(this, args)
            }
        """.trimIndent()

        /**
         * What the engine gets while the proxy runs: Node 24's own proxy support
         * (NODE_USE_ENV_PROXY) pointed at a loopback [port] nothing listens on, which
         * [PRELOAD] turns into the core's [socket]. Loopback itself stays direct: the app
         * talks to the engine there. [nodeOptions] is what the launch already has.
         */
        fun engineEnv(port: Int, socket: String, auth: Pair<String, String>, nodeOptions: String?): Map<String, String> {
            val url = "http://${auth.first}:${auth.second}@$LOOPBACK:$port"
            val direct = "localhost,127.0.0.1,::1"
            val preload = "--import=data:text/javascript," + java.net.URLEncoder.encode(PRELOAD, "UTF-8").replace("+", "%20")
            val env = linkedMapOf(
                "NODE_USE_ENV_PROXY" to "1",
                ENV_PORT to port.toString(),
                ENV_SOCKET to socket,
                "NODE_OPTIONS" to listOfNotNull(nodeOptions?.ifBlank { null }, preload).joinToString(" "),
            )
            for (name in PROXY_NAMES) env[name] = if (name.lowercase() == "no_proxy") direct else url
            return env
        }
    }
}
