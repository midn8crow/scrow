#!/bin/bash
win=$(hyprctl activewindow -j 2>/dev/null) || exit 0
ws=$(echo "$win" | python3 -c "import sys,json; print(json.load(sys.stdin).get('workspace',{}).get('name',''))")
if [ "$ws" = "special:magic" ]; then
    target=$(hyprctl monitors -j | python3 -c "import sys,json; print(json.load(sys.stdin)[0]['activeWorkspace']['id'])")
    hyprctl dispatch "hl.dsp.window.move({ workspace = $target })"
    hyprctl eval 'hl.dispatch(hl.dsp.window.set_prop({prop="no_blur",value="unset"}))'
    hyprctl eval 'hl.dispatch(hl.dsp.window.set_prop({prop="opacity_override",value="unset"}))'
else
    hyprctl dispatch 'hl.dsp.window.move({ workspace = "special:magic" })'
    hyprctl eval 'hl.dispatch(hl.dsp.window.set_prop({prop="no_blur",value="1"}))'
    hyprctl eval 'hl.dispatch(hl.dsp.window.set_prop({prop="opacity_override",value="1"}))'
    hyprctl eval 'hl.dispatch(hl.dsp.window.set_prop({prop="opacity",value="0.7"}))'
fi
