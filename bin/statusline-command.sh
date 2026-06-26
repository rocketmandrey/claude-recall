#!/bin/bash

# Claude Code Status Line — project [addr] | 5h/7d limits | ctx | effort | model
input=$(cat)

# Extract fields
model_id=$(echo "$input" | jq -r '.model.id // "unknown"')
current_dir=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
session_id=$(echo "$input" | jq -r '.session_id // empty')

# Project name from directory
dir_name=$(basename "${current_dir:-$(pwd)}")
project_name="$dir_name"

# --- Unique session handle for addressing ---
# Prefer the iTerm tty (e.g. s053) — that's how the orchestrator injects directly.
# The statusline script runs piped (no own tty), so walk UP the process tree:
# an ancestor (claude itself) holds the real controlling terminal.
sess_handle=""
pid=$$
depth=0
while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null && [ "$depth" -lt 6 ]; do
    t=$(ps -o tty= -p "$pid" 2>/dev/null | tr -d ' ')
    if [ -n "$t" ] && [ "$t" != "??" ]; then
        sess_handle="${t#tty}"          # ttys053 -> s053
        break
    fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null | tr -d ' ')
    depth=$((depth + 1))
done
# Fallback to short session_id if no controlling tty found anywhere up the tree
[ -z "$sess_handle" ] && sess_handle="${session_id:0:8}"
[ -z "$sess_handle" ] && sess_handle="?"

# Rate limits (available for Pro/Max subscribers, v2.1.80+)
five_hr=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // empty')
five_hr_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // empty')
seven_day=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // empty')
seven_day_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // empty')

# Build limits display
limits=""
if [ -n "$five_hr" ] && [ "$five_hr" != "null" ]; then
    five_remain=$(awk "BEGIN {printf \"%.0f\", 100 - $five_hr}")

    five_reset_str=""
    if [ -n "$five_hr_reset" ] && [ "$five_hr_reset" != "null" ]; then
        now=$(date +%s)
        diff=$(( five_hr_reset - now ))
        if [ $diff -gt 0 ]; then
            h=$(( diff / 3600 ))
            m=$(( (diff % 3600) / 60 ))
            if [ $h -ge 1 ]; then
                five_reset_str=" ${h}h${m}m"
            else
                five_reset_str=" ${m}m"
            fi
        fi
    fi

    if [ "$five_remain" -gt 50 ]; then
        five_color="\033[32m"
    elif [ "$five_remain" -gt 20 ]; then
        five_color="\033[33m"
    else
        five_color="\033[31m"
    fi

    limits="${five_color}5h:${five_remain}%${five_reset_str}\033[0m"
fi

if [ -n "$seven_day" ] && [ "$seven_day" != "null" ]; then
    seven_remain=$(awk "BEGIN {printf \"%.0f\", 100 - $seven_day}")

    seven_reset_str=""
    if [ -n "$seven_day_reset" ] && [ "$seven_day_reset" != "null" ]; then
        now=$(date +%s)
        diff=$(( seven_day_reset - now ))
        if [ $diff -gt 0 ]; then
            d=$(( diff / 86400 ))
            h=$(( (diff % 86400) / 3600 ))
            if [ $d -ge 1 ]; then
                seven_reset_str=" ${d}d${h}h"
            else
                seven_reset_str=" ${h}h"
            fi
        fi
    fi

    if [ "$seven_remain" -gt 50 ]; then
        seven_color="\033[32m"
    elif [ "$seven_remain" -gt 20 ]; then
        seven_color="\033[33m"
    else
        seven_color="\033[31m"
    fi

    if [ -n "$limits" ]; then
        limits="${limits} ${seven_color}7d:${seven_remain}%${seven_reset_str}\033[0m"
    else
        limits="${seven_color}7d:${seven_remain}%${seven_reset_str}\033[0m"
    fi
fi

# Fallback if no rate limit data yet
if [ -z "$limits" ]; then
    limits="\033[90mwaiting...\033[0m"
fi

# Context window usage
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
ctx=""
if [ -n "$ctx_pct" ] && [ "$ctx_pct" != "null" ]; then
    ctx_int=$(awk "BEGIN {printf \"%.0f\", $ctx_pct}")
    if [ "$ctx_int" -lt 50 ]; then
        ctx_color="\033[32m"
    elif [ "$ctx_int" -lt 80 ]; then
        ctx_color="\033[33m"
    else
        ctx_color="\033[31m"
    fi
    ctx="${ctx_color}ctx:${ctx_int}%\033[0m"
fi

# Short model name — detect 1M context variant
ctx_suffix=""
case "$model_id" in
    *\[1m\]*|*-1m*|*_1m*) ctx_suffix=" 1M" ;;
esac

case "$model_id" in
    *opus*4-8*|*opus-4-8*|*opus*4*8*)       model_base="opus4.8" ;;
    *opus*4-7*|*opus-4-7*|*opus*4*7*)       model_base="opus4.7" ;;
    *opus*4-6*|*opus-4-6*|*opus*4*6*)       model_base="opus4.6" ;;
    *opus*4-5*|*opus-4-5*|*opus*4*5*)       model_base="opus4.5" ;;
    *sonnet*4-6*|*sonnet-4-6*|*sonnet*4*6*) model_base="sonnet4.6" ;;
    *sonnet*4-5*|*sonnet-4-5*|*sonnet*4*5*) model_base="sonnet4.5" ;;
    *sonnet*4*|*sonnet-4*)                  model_base="sonnet4" ;;
    *haiku*4-5*|*haiku-4-5*)                model_base="haiku4.5" ;;
    *haiku*)                                model_base="haiku" ;;
    *fable*5*|*fable-5*)                    model_base="fable5" ;;
    *)                                      model_base="${model_id:-claude}" ;;
esac
model_short="${model_base}${ctx_suffix}"

# Effort level from settings.json (compact: e:xh/hi/md/lo)
effort=""
effort_level=$(jq -r '.effortLevel // empty' ~/.claude/settings.json 2>/dev/null)
if [ -n "$effort_level" ]; then
    case "$effort_level" in
        xhigh)  effort_abbr="xh"; effort_color="\033[35m" ;;
        high)   effort_abbr="hi"; effort_color="\033[35m" ;;
        medium) effort_abbr="md"; effort_color="\033[33m" ;;
        low)    effort_abbr="lo"; effort_color="\033[90m" ;;
        *)      effort_abbr="$effort_level"; effort_color="\033[37m" ;;
    esac
    effort="${effort_color}e:${effort_abbr}\033[0m"
fi

# Assemble: project [addr] | limits | ctx | effort | model   (cost removed)
parts="$limits"
[ -n "$ctx" ] && parts="$parts | $ctx"
[ -n "$effort" ] && parts="$parts | $effort"

printf "• %s \033[1;36m[%s]\033[0m | %b | %s" "$project_name" "$sess_handle" "$parts" "$model_short"
