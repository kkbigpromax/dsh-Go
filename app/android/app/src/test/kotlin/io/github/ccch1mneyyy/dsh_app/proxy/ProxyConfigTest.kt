package io.github.ccch1mneyyy.dsh_app.proxy

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ProxyConfigTest {
    private val vision = ProxyConfig(
        enabled = true,
        address = " proxy.example.com ",
        port = 443,
        id = "b831381d-6324-4d53-ad4f-8cda48b30811",
        sni = "www.example.com",
        publicKey = "Z84J2IelR9ch3k8VtlVhhs5ycBUlXA7wHBWcBrjqnAw",
        shortId = "6ba85179e30d4fc2",
    )

    @Test fun visionOverRawIsAnHttpProxyToOneRealityServer() {
        val json = vision.xray(10809, listOf("223.5.5.5"))
        val inbound = json.getJSONArray("inbounds").getJSONObject(0)
        assertEquals("http", inbound.getString("protocol"))
        assertEquals("127.0.0.1", inbound.getString("listen"))
        assertEquals(10809, inbound.getInt("port"))
        val outbounds = json.getJSONArray("outbounds")
        assertEquals(1, outbounds.length())
        val out = outbounds.getJSONObject(0)
        assertEquals("vless", out.getString("protocol"))
        val settings = out.getJSONObject("settings")
        assertEquals("proxy.example.com", settings.getString("address"))
        assertEquals("xtls-rprx-vision", settings.getString("flow"))
        assertEquals("none", settings.getString("encryption"))
        val stream = out.getJSONObject("streamSettings")
        assertEquals("raw", stream.getString("network"))
        assertEquals("reality", stream.getString("security"))
        assertFalse(stream.has("xhttpSettings"))
        // The server's name resolves through Xray's own DNS, not Android's missing resolv.conf.
        assertEquals("UseIP", stream.getJSONObject("sockopt").getString("domainStrategy"))
        val reality = stream.getJSONObject("realitySettings")
        assertEquals("www.example.com", reality.getString("serverName"))
        assertEquals("chrome", reality.getString("fingerprint"))
        assertFalse(reality.has("spiderX"))
        assertEquals("223.5.5.5", json.getJSONObject("dns").getJSONArray("servers").getString(0))
    }

    @Test fun xhttpDropsTheRawOnlyFlowAndCarriesItsSettings() {
        val config = vision.copy(network = ProxyConfig.NETWORK_XHTTP, xhttpPath = "/abc", xhttpMode = "packet-up", xhttpHost = "cdn.example.com")
        val out = config.xray(1080, emptyList()).getJSONArray("outbounds").getJSONObject(0)
        assertFalse(out.getJSONObject("settings").has("flow"))
        val xhttp = out.getJSONObject("streamSettings").getJSONObject("xhttpSettings")
        assertEquals("/abc", xhttp.getString("path"))
        assertEquals("packet-up", xhttp.getString("mode"))
        assertEquals("cdn.example.com", xhttp.getString("host"))
    }

    @Test fun problemsNameTheField() {
        assertNull(vision.problem())
        assertEquals("address", vision.copy(address = " ").problem())
        assertEquals("port", vision.copy(port = 0).problem())
        assertEquals("id", vision.copy(id = "").problem())
        assertEquals("publicKey", vision.copy(publicKey = "").problem())
        assertEquals("flow", vision.copy(flow = "xtls-rprx-direct").problem())
        assertEquals("xhttpMode", vision.copy(network = ProxyConfig.NETWORK_XHTTP, xhttpMode = "grpc").problem())
    }

    @Test fun jsonRoundTripsAndDefaultsFillGaps() {
        assertEquals(vision, ProxyConfig.fromJson(vision.toJson()))
        assertEquals(ProxyConfig(), ProxyConfig.fromJson(null))
        assertFalse(ProxyConfig().enabled)
    }

    @Test fun theEngineKeepsLoopbackDirect() {
        val env = ProxyConfig.engineEnv(20000)
        assertEquals("1", env["NODE_USE_ENV_PROXY"])
        assertEquals("http://127.0.0.1:20000", env["HTTPS_PROXY"])
        assertTrue(env.getValue("NO_PROXY").split(',').containsAll(listOf("localhost", "127.0.0.1", "::1")))
    }
}
