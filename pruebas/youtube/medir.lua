-- Marca para la prueba: cuándo empieza a verse el video y con qué formato.
local t0 = mp.get_time()
local ya = false
mp.register_event("playback-restart", function()
    if ya then return end
    ya = true
    local vp = mp.get_property_native("video-params") or {}
    io.stderr:write(string.format(
        "MEDIR-INICIO segundos_en_mpv=%.2f codec=%s alto=%s fps=%s hwdec=%s audio=%s\n",
        mp.get_time() - t0,
        tostring(mp.get_property("video-codec")),
        tostring(vp.h), tostring(mp.get_property("container-fps")),
        tostring(mp.get_property("hwdec-current")),
        tostring(mp.get_property("audio-codec-name"))))
    io.stderr:flush()
    mp.add_timeout(40, function()
        io.stderr:write(string.format("MEDIR-FIN cuadros_perdidos=%s\n",
            tostring(mp.get_property("frame-drop-count"))))
        io.stderr:flush()
        mp.command("quit")
    end)
end)
