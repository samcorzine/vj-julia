using FileIO
using Makie
using VideoIO
import Dates

Rot(theta) = [cos(theta) -sin(theta); sin(theta) cos(theta)]
Stretch(length) = [length 0.0f0; 0.0f0 1.0f0]
Scale(length) = [length 0.0f0; 0.0f0 length]
pulse(t, length) = t < length && t > 0.0f0 ? 1 - (1/length * t) : 0
range_mask(low, high) = val -> val > low && val < high ? 1.0f0 : 0.0f0

function c(x, y, t, kick_val)
    transform = Stretch(0.5 * (kick_val + 1)) * Rot(t) * Scale(0.5)
    trans_x, trans_y = transform * [x, y]
    val = (trans_x * trans_x) + (trans_y * trans_y)
    return val
end

function gridder(frame_size, depth, val_func, events, framerate)
    framestack = []
    kicks = [event["time"] for event in events]
    println(kicks)
    for t in 1:depth
        curr_time = t/framerate
        past_kicks = filter(p -> p < curr_time, kicks)
        last_kick_time = length(past_kicks) > 0 ? maximum(past_kicks) : curr_time
        kick_val = pulse(curr_time - last_kick_time, 1.0f0)
        x = reshape(range(-10.0f0, 10.0f0, length = frame_size), (1, frame_size))
        y = reshape(range(-10.0f0, 10.0f0, length = frame_size), (frame_size, 1))
        out_vals = val_func.(x, y, curr_time, kick_val)
        masked = range_mask(0.0f0, 1.1f0).(out_vals)
        push!(framestack, masked)
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
    midiFile = MIDI.readMIDIFile("test-midi.mid")
    drum_track = midiFile.tracks[1]
    notes = MIDI.getnotes(drum_track, midiFile.tpq)
    seconds_per_tick = MIDI.ms_per_tick(midiFile) / 1000
    drum_events = [
        Dict("time" => float(x.position) * seconds_per_tick, "type" => "kick")
        for x=notes.notes
    ]
    return drum_events
end

# events = [video_renderer("test-full", gridder(500, 1000, c, map_midi_to_events("test-midi.mid"), 60), 60)
# video_renderer("$(abs(rand(Int)[1]))", gridder(500, 100, c, events, 10), 10)