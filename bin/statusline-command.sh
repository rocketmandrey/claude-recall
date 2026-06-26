#!/bin/bash
# Claude Code Status Line (fast) — • project [addr] | 5h/7d | ctx | e:xx | model
# Optimized: ONE jq for all input fields, tty cached per-session (ps-walk runs once),
# bash arithmetic instead of awk, builtin basename. ~3 forks/render vs ~20 before.
input=$(cat)

# --- single jq: pull every input field at once ---
IFS=$'\t' read -r model_id current_dir session_id five_hr five_reset seven_day seven_reset ctx_pct < <(
  printf '%s' "$input" | jq -r '[
    (.model.id // "unknown"),
    (.workspace.current_dir // .cwd // ""),
    (.session_id // ""),
    (.rate_limits.five_hour.used_percentage // ""),
    (.rate_limits.five_hour.resets_at // ""),
    (.rate_limits.seven_day.used_percentage // ""),
    (.rate_limits.seven_day.resets_at // ""),
    (.context_window.used_percentage // "")
  ] | @tsv'
)

project_name="${current_dir##*/}"; [ -z "$project_name" ] && project_name="claude"

# --- session handle (iTerm tty) cached per session: ps-walk only on first render ---
sid8="${session_id:0:8}"
cache="/tmp/.recall_tty_${sid8:-x}"
sess_handle=""; [ -s "$cache" ] && read -r sess_handle < "$cache"
if [ -z "$sess_handle" ]; then
  pid=$$; depth=0; found=""
  while [ -n "$pid" ] && [ "$pid" -gt 1 ] 2>/dev/null && [ "$depth" -lt 6 ]; do
    t=$(ps -o tty= -p "$pid" 2>/dev/null); t="${t// /}"
    if [ -n "$t" ] && [ "$t" != "??" ]; then sess_handle="${t#tty}"; found=1; break; fi
    pid=$(ps -o ppid= -p "$pid" 2>/dev/null); pid="${pid// /}"; depth=$((depth+1))
  done
  if [ -n "$found" ]; then
    printf '%s' "$sess_handle" > "$cache" 2>/dev/null   # cache only a REAL tty
  else
    sess_handle="${sid8:-?}"                            # fallback, not cached (retry next render)
  fi
fi

now=$(date +%s)

# --- 5h limit ---
limits=""
if [ -n "$five_hr" ]; then
  rem=$(( 100 - ${five_hr%%.*} )); rs=""
  if [ -n "$five_reset" ]; then d=$(( ${five_reset%%.*} - now )); if [ "$d" -gt 0 ]; then h=$((d/3600)); m=$(((d%3600)/60)); if [ "$h" -ge 1 ]; then rs=" ${h}h${m}m"; else rs=" ${m}m"; fi; fi; fi
  if [ "$rem" -gt 50 ]; then c="\033[32m"; elif [ "$rem" -gt 20 ]; then c="\033[33m"; else c="\033[31m"; fi
  limits="${c}5h:${rem}%${rs}\033[0m"
fi
# --- 7d limit ---
if [ -n "$seven_day" ]; then
  rem=$(( 100 - ${seven_day%%.*} )); rs=""
  if [ -n "$seven_reset" ]; then d=$(( ${seven_reset%%.*} - now )); if [ "$d" -gt 0 ]; then dd=$((d/86400)); h=$(((d%86400)/3600)); if [ "$dd" -ge 1 ]; then rs=" ${dd}d${h}h"; else rs=" ${h}h"; fi; fi; fi
  if [ "$rem" -gt 50 ]; then c="\033[32m"; elif [ "$rem" -gt 20 ]; then c="\033[33m"; else c="\033[31m"; fi
  if [ -n "$limits" ]; then limits="${limits} ${c}7d:${rem}%${rs}\033[0m"; else limits="${c}7d:${rem}%${rs}\033[0m"; fi
fi
[ -z "$limits" ] && limits="\033[90mwaiting...\033[0m"

# --- ctx ---
ctx=""
if [ -n "$ctx_pct" ]; then
  ci=${ctx_pct%%.*}
  if [ "$ci" -lt 50 ]; then c="\033[32m"; elif [ "$ci" -lt 80 ]; then c="\033[33m"; else c="\033[31m"; fi
  ctx="${c}ctx:${ci}%\033[0m"
fi

# --- model (compact) ---
sfx=""; case "$model_id" in *\[1m\]*|*-1m*|*_1m*) sfx=" 1M";; esac
case "$model_id" in
  *opus*4-8*|*opus*4*8*)     mb="opus4.8";;
  *opus*4-7*|*opus*4*7*)     mb="opus4.7";;
  *opus*4-6*|*opus*4*6*)     mb="opus4.6";;
  *opus*4-5*|*opus*4*5*)     mb="opus4.5";;
  *sonnet*4-6*|*sonnet*4*6*) mb="sonnet4.6";;
  *sonnet*4-5*|*sonnet*4*5*) mb="sonnet4.5";;
  *sonnet*4*)                mb="sonnet4";;
  *haiku*4-5*)               mb="haiku4.5";;
  *haiku*)                   mb="haiku";;
  *fable*5*)                 mb="fable5";;
  *)                         mb="${model_id:-claude}";;
esac
model_short="${mb}${sfx}"

# --- effort (from settings.json) ---
effort=""
el=$(jq -r '.effortLevel // empty' ~/.claude/settings.json 2>/dev/null)
if [ -n "$el" ]; then
  case "$el" in
    xhigh)  ea="xh"; ec="\033[35m";;
    high)   ea="hi"; ec="\033[35m";;
    medium) ea="md"; ec="\033[33m";;
    low)    ea="lo"; ec="\033[90m";;
    *)      ea="$el"; ec="\033[37m";;
  esac
  effort="${ec}e:${ea}\033[0m"
fi

parts="$limits"
[ -n "$ctx" ] && parts="$parts | $ctx"
[ -n "$effort" ] && parts="$parts | $effort"
printf "• %s \033[1;36m[%s]\033[0m | %b | %s" "$project_name" "$sess_handle" "$parts" "$model_short"
