--[[
Cut a fragment of the playing file with ffmpeg.

Keybindings: c — mark start, again to mark end and write the cut
             C — clear the mark
Config:      ~~/script-opts/slicing.conf
Options:     target_dir=~~/cutfragments, ffmpeg_path=ffmpeg,
             vcodec=copy, acodec=copy, overwrite=false, debug=false
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
    debug = false,
}
options.read_options(opts)

local cut_pos = nil
local ext_map = {
    ["mpegts"] = "ts",
}

local function trim(s)
    return (s:gsub("^%s*(.-)%s*$", "%1"))
end

local function file_format()
    local fmt = mp.get_property("file-format")
    if not fmt:find(",") then
        return fmt
    end
    local filename = mp.get_property("filename")
    local name = mp.get_property("filename/no-ext")
    return filename:sub(name:len() + 2)
end

local function get_ext()
    local fmt = file_format()
    return ext_map[fmt] or fmt
end

local function timestamp(duration)
    local hours = math.floor(duration / 3600)
    local minutes = math.floor(duration % 3600 / 60)
    local seconds = duration % 60
    return string.format("%02d:%02d:%06.3f", hours, minutes, seconds)
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
    return name:gsub(":", "-")
end

local function cut(shift, endpos)
    local inpath = mp.get_property("stream-open-filename")
    local outpath = utils.join_path(opts.target_dir, get_outname(shift, endpos))
    local ua = mp.get_property("user-agent")
    local referer = mp.get_property("referrer")
    local args = { opts.ffmpeg_path, "-v", "warning", opts.overwrite and "-y" or "-n", "-stats" }
    local function add(...)
        for _, v in ipairs({ ... }) do
            args[#args + 1] = v
        end
    end
    if is_remote() and ua and ua ~= "" and ua ~= "libmpv" then
        add("-user_agent", ua)
    end
    if referer and referer ~= "" then
        add("-referer", referer)
    end
    add("-ss", tostring(shift), "-accurate_seek", "-i", inpath)
    add("-t", tostring(endpos - shift))
    add("-c:v", opts.vcodec, "-c:a", opts.acodec, "-c:s", "copy")
    local video_id = mp.get_property_number("current-tracks/video/id")
    local audio_id = mp.get_property_number("current-tracks/audio/id")
    local sub_id = mp.get_property_number("current-tracks/sub/id")
    if video_id then
        add("-map", string.format("v:%d?", video_id - 1))
    end
    if audio_id then
        add("-map", string.format("a:%d?", audio_id - 1))
    end
    if sub_id then
        add("-map", string.format("s:%d?", sub_id - 1))
    end
    add("-avoid_negative_ts", "make_zero", "-async", "1", outpath)

    msg.info("Run commands: " .. table.concat(args, " "))
    local res, err = mp.command_native({
        name = "subprocess",
        args = args,
        capture_stdout = true,
        capture_stderr = true,
    })
    if err then
        msg.error(utils.to_string(err))
        mp.osd_message("Failed. Refer console for details.")
    elseif res.status ~= 0 then
        if res.stderr ~= "" or res.stdout ~= "" then
            msg.info("stderr: " .. trim(res.stderr))
            msg.info("stdout: " .. trim(res.stdout))
            mp.osd_message("Failed. Refer console for details.")
        end
    else
        if opts.debug and (res.stderr ~= "" or res.stdout ~= "") then
            msg.info("stderr: " .. trim(res.stderr))
            msg.info("stdout: " .. trim(res.stdout))
        end
        msg.info("Trim file successfully created: " .. outpath)
    end
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

opts.target_dir = opts.target_dir:gsub('"', "")
local target_dir = mp.command_native({ "expand-path", opts.target_dir })
local file = utils.file_info(target_dir)
if not file then
    local is_windows = package.config:sub(1, 1) == "\\"
    local windows_args = { "powershell", "-NoProfile", "-Command", "mkdir", string.format('"%s"', target_dir) }
    local unix_args = { "mkdir", "-p", target_dir }
    local args = is_windows and windows_args or unix_args
    local res = mp.command_native({ name = "subprocess", capture_stdout = true, playback_only = false, args = args })
    if res.status ~= 0 then
        msg.error(
            "Failed to create target_dir save directory " .. target_dir .. ". Error: " .. (res.error or "unknown")
        )
        return
    end
elseif not file.is_dir then
    osd("target_dir is a file")
    msg.warn(string.format("target_dir `%s` is a file", target_dir))
end
opts.target_dir = target_dir

mp.add_key_binding("c", "slicing_mark", toggle_mark)
mp.add_key_binding("C", "clear_slicing_mark", clear_toggle_mark)
