using FileIO
using Makie
using VideoIO
using Colors
using ProgressBars
import Dates
import MIDI

Rot(theta) = [cos(theta) -sin(theta); sin(theta) cos(theta)]
Stretch(length) = [length 0.0f0; 0.0f0 1.0f0]
Scale(length) = [length 0.0f0; 0.0f0 length]
pulse(t, length) = t < length && t > 0.0f0 ? 1 - (1/length * t) : 0
range_mask(low, high) = val -> val > low && val < high ? 1.0f0 : 0.0f0
cast_to(r, g, b) = val -> val == 1.0f0 ? RGB(r, g, b) : RGB(0, 0, 0)

function circle(x, y, t, kick_val, snare_count)
    transform = Rot(pi/4 + t) * Scale(1 / (kick_val + 1))
#     transform = Rot(0)
    trans_x, trans_y = transform * [x, y]
    val = tan(((trans_x * trans_x) + sin(t)) + ((trans_y * trans_y) + sin(t)))
    return val
end

function square(x, y, t, kick_val, snare_count)
    transform = Rot(pi/4 + t) * Scale(1 / (kick_val + 1) )
    trans_x, trans_y = transform * [x, y]
    val = sin((abs(trans_x) + abs(trans_y)) * tan(snare_count))
    return val
end

function gridder(frame_size, depth, val_func, events, framerate)
    framestack = []
    kicks = [event["time"] for event in filter(e -> e["type"] == "kick", events)]
    snares = [event["time"] for event in filter(e -> e["type"] == "snare", events)]
    synth_events = filter(e -> e["type"] == "synth", events)
    for t in ProgressBar(1:depth)
        curr_time = t/framerate
        past_kicks = filter(p -> p < curr_time, kicks)
        last_kick_time = length(past_kicks) > 0 ? maximum(past_kicks) : curr_time
        kick_val = pulse(curr_time - last_kick_time, 0.6f0)
        past_snares = filter(p -> p < curr_time, snares)
        snare_count = length(past_snares)
        past_synth_events = filter(p -> p["time"] < curr_time, synth_events)
        last_synth_pitch = sort(past_synth_events, by=e->e["time"])[length(past_synth_events)]["pitch"] % 12
        r = last_synth_pitch % 1 == 0 ? 1 : 0
        g = last_synth_pitch % 2 == 0 ? 1 : 0
        b = last_synth_pitch % 5 == 0 ? 1 : 0

        x = reshape(range(-20.0f0, 20.0f0, length = frame_size), (1, frame_size))
        y = reshape(range(-20.0f0, 20.0f0, length = frame_size), (frame_size, 1))
        out_vals = val_func.(x, y, curr_time, kick_val, snare_count)
        masked = range_mask(0.0f0, 1.1f0).(out_vals)
        with_color = cast_to(r, g, b).(masked)
        push!(framestack, with_color)
    end
    return framestack
end


function video_renderer(name, frames, framerate)
    timestamp = Dates.now()
    frame_count = length(frames)
    for i = 1:frame_count
        save("$(timestamp)/test$(i).png", frames[i])
    end
    imgstack = []
    for i in 1:frame_count
        push!(imgstack,load("$(timestamp)/test$(i).png"))
    end
    props = [:priv_data => ("preset"=>"medium")]
    encodevideo("$(name).mp4",imgstack,framerate=framerate,AVCodecContextProperties=props)
    f = VideoIO.open("$(name).mp4")
    VideoIO.playvideo(f)
end

function map_midi_to_events(midi_path)
    midiFile = MIDI.readMIDIFile(midi_path)
    drum_track = midiFile.tracks[1]
    notes = MIDI.getnotes(drum_track, midiFile.tpq)
    seconds_per_tick = MIDI.ms_per_tick(midiFile) / 1000
    kick_events = [
        Dict("time" => float(x.position) * seconds_per_tick, "type" => "kick")
        for x=filter(note -> note.pitch == 0x24, notes.notes)
    ]
    snare_events = [
        Dict("time" => float(x.position) * seconds_per_tick, "type" => "snare")
        for x=filter(note -> note.pitch == 0x25, notes.notes)
    ]
    synth_track = midiFile.tracks[2]
    synth_notes = MIDI.getnotes(synth_track, midiFile.tpq)
    synth_events = [
        Dict("time" => float(x.position) * seconds_per_tick, "type" => "synth", "pitch" => x.pitch, "duration" => x.duration * seconds_per_tick)
        for x=synth_notes.notes
    ]
    return vcat(kick_events, snare_events, synth_events)
end

framerate = 20
video_renderer("test-full", gridder(500, 1000, square, map_midi_to_events("test-midi-2.mid"), framerate), framerate)