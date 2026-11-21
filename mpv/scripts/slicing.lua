--[[
Cut a fragment of the playing file with ffmpeg.

Keybindings: c — mark start, again to mark end and write the cut
             C — clear the mark
Config:      ~~/script-opts/slicing.conf
Options:     target_dir=~~/cutfragments, ffmpeg_path=ffmpeg,
             vcodec=copy, acodec=copy, overwrite=false
--]]

local mp = require("mp")
local msg = require("mp.msg")
local options = require("mp.options")
local utils = require("mp.utils")

local opts = {
    ffmpeg_path = "ffmpeg",
    target_dir = "~~/cutfragments",
    overwrite = false,
    vcodec = "copy",
    acodec = "copy",
}
options.read_options(opts)

local cut_pos = nil
local ext_map = {
    ["mpegts"] = "ts",
}

local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function get_ext()
    local fmt = mp.get_property("file-format")
    if fmt:find(",") then
        return mp.get_property("filename"):match("%.([^.]+)$") or "mkv"
    end
    return ext_map[fmt] or fmt
end

local function timestamp(seconds)
    return mp.format_time(seconds, "%H:%M:%S.%T")
end

local function osd(str)
    mp.osd_message(str, 3)
end

local function info(s)
    msg.info(s)
    osd(s)
end

local function is_remote()
    return mp.get_property("path"):find("://", 1, true) ~= nil
end

local function get_outname(shift, endpos)
    local name = mp.get_property("filename/no-ext")
    local ext = get_ext()
    name = string.format("%s_%s-%s.%s", name, timestamp(shift), timestamp(endpos), ext)
    return (name:gsub(":", "-"))
end

local function cut(shift, endpos)
    local inpath = mp.get_property("stream-open-filename")
    if inpath:find("^edl://") then
        info("Can't cut this stream: ffmpeg can't read mpv EDL")
        return
    end
    local target_dir = mp.command_native({ "expand-path", opts.target_dir })
    local dir = utils.file_info(target_dir)
    if not (dir and dir.is_dir) then
        msg.error("target_dir is not an existing directory: " .. target_dir)
        osd("Cut failed, see console")
        return
    end
    local outpath = utils.join_path(target_dir, get_outname(shift, endpos))
    local args = { opts.ffmpeg_path, "-v", "warning", opts.overwrite and "-y" or "-n" }
    local function add(...)
        for _, v in ipairs({ ... }) do
            args[#args + 1] = v
        end
    end
    if is_remote() then
        local ua = mp.get_property("user-agent")
        local referer = mp.get_property("referrer")
        if ua ~= "" and ua ~= "libmpv" then
            add("-user_agent", ua)
        end
        if referer ~= "" then
            add("-referer", referer)
        end
    end
    add("-ss", tostring(shift), "-i", inpath)
    add("-t", tostring(endpos - shift))
    add("-c:v", opts.vcodec, "-c:a", opts.acodec, "-c:s", "copy")
    for _, kind in ipairs({ "video", "audio", "sub" }) do
        local track = mp.get_property_native("current-tracks/" .. kind)
        if track and track.external then
            msg.warn(string.format("External %s track is not included in the cut", kind))
        elseif track and track["ff-index"] then
            add("-map", "0:" .. track["ff-index"])
        end
    end
    add("-avoid_negative_ts", "make_zero", outpath)

    msg.verbose("Run: " .. table.concat(args, " "))
    local res, err = mp.command_native({ name = "subprocess", args = args, capture_stderr = true })
    if err or res.status ~= 0 then
        msg.error(err or string.format("ffmpeg exited with %d: %s", res.status, trim(res.stderr)))
        osd("Cut failed, see console")
        return
    end
    if res.stderr ~= "" then
        msg.warn(trim(res.stderr))
    end
    info("Saved " .. outpath)
end

local function toggle_mark()
    local pos, err = mp.get_property_number("time-pos")
    if not pos then
        osd("Failed to get timestamp")
        msg.error("Failed to get timestamp: " .. err)
        return
    end
    if cut_pos then
        local shift, endpos = cut_pos, pos
        if shift > endpos then
            shift, endpos = endpos, shift
        elseif shift == endpos then
            osd("Cut fragment is empty")
            return
        end
        cut_pos = nil
        info(string.format("Cut fragment: %s-%s", timestamp(shift), timestamp(endpos)))
        cut(shift, endpos)
    else
        cut_pos = pos
        info(string.format("Marked %s as start position", timestamp(pos)))
    end
end

local function clear_toggle_mark()
    cut_pos = nil
    info("Cleared cut fragment")
end

mp.register_event("file-loaded", function()
    cut_pos = nil
end)

mp.add_key_binding("c", "slicing_mark", toggle_mark)
mp.add_key_binding("C", "clear_slicing_mark", clear_toggle_mark)
