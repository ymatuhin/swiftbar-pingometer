# <xbar.title>Pingometer</xbar.title>
# <xbar.version>v2</xbar.version>
# <xbar.author>ymatuhin</xbar.author>
# <xbar.github>https://github.com/ymatuhin/swiftbar-pingometer</xbar.github>
# <xbar.desc>Display connection stability info (median/jitter/loss)</xbar.desc>
# <xbar.about>https://ymatuhin.ru</xbar.about>
# <xbar.dependencies>curl</xbar.dependencies>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>

PRIMARY_ENDPOINT="https://ya.ru/favicon.ico"
SECONDARY_ENDPOINT="https://gstatic.com/generate_204"
TOTAL_BUDGET_MS=1950
CONNECT_TIMEOUT=0.45
MAX_TIME=0.5

is_dark_mode() {
  [ "$(defaults read -g AppleInterfaceStyle 2>/dev/null)" = "Dark" ]
}

round_to_even() {
  local n="$1"
  if [ $((n % 2)) -eq 0 ]; then
    echo "$n"
  else
    echo $((n + 1))
  fi
}

pick_color() {
  local loss="$1"
  local jitter="$2"

  if [ "$loss" -gt 50 ] || [ "$jitter" -gt 120 ]; then
    echo "$RED"
  elif [ "$loss" -gt 25 ] || [ "$jitter" -gt 80 ]; then
    echo "$ORANGE"
  elif [ "$loss" -gt 0 ] || [ "$jitter" -gt 40 ]; then
    echo "$YELLOW"
  else
    echo "$GREEN"
  fi
}

probe_appconnect_ms() {
  local endpoint="$1"
  local seconds
  local ms

  seconds="$(
    curl -o /dev/null -sS \
      --connect-timeout "$CONNECT_TIMEOUT" \
      --max-time "$MAX_TIME" \
      -w '%{time_appconnect}' \
      "$endpoint" 2>/dev/null
  )"

  if [ -z "$seconds" ] || [ "$seconds" = "0.000000" ]; then
    return 1
  fi

  ms="$(awk -v s="$seconds" 'BEGIN { printf "%.0f", s * 1000 }')"
  if [ -z "$ms" ] || [ "$ms" -le 0 ]; then
    return 1
  fi

  echo "$ms"
}

now_ms() {
  perl -MTime::HiRes=time -e 'printf "%.0f\n", time()*1000'
}

compute_median() {
  awk '
    { a[NR] = $1 }
    END {
      if (NR == 0) { print 0; exit }
      if (NR % 2 == 1) { print a[(NR + 1) / 2]; exit }
      print int((a[NR / 2] + a[NR / 2 + 1]) / 2)
    }
  '
}

compute_p90() {
  awk '
    { a[NR] = $1 }
    END {
      if (NR == 0) { print 0; exit }
      idx = int((NR * 90 + 99) / 100)
      if (idx < 1) idx = 1
      if (idx > NR) idx = NR
      print a[idx]
    }
  '
}

if is_dark_mode; then
  RED="#FF453A"
  ORANGE="#FF9F0B"
  YELLOW="#FFD609"
  GREEN="#32D74B"
else
  RED="#FF3B2F"
  ORANGE="#FF9500"
  YELLOW="#FFCC02"
  GREEN="#27CD41"
fi

primary_samples=()
secondary_samples=()
primary_attempts=0
primary_failed=0
secondary_attempts=0
secondary_failed=0

start_ms="$(now_ms)"
deadline_ms=$((start_ms + TOTAL_BUDGET_MS))

# Alternate RU and OUT probes until the 1.9s budget is exhausted.
while :; do
  current_ms="$(now_ms)"
  if [ "$current_ms" -ge "$deadline_ms" ]; then
    break
  fi

  primary_attempts=$((primary_attempts + 1))
  sample="$(probe_appconnect_ms "$PRIMARY_ENDPOINT")"
  if [ -n "$sample" ]; then
    primary_samples+=("$sample")
  else
    primary_failed=$((primary_failed + 1))
  fi

  current_ms="$(now_ms)"
  if [ "$current_ms" -ge "$deadline_ms" ]; then
    break
  fi

  secondary_attempts=$((secondary_attempts + 1))
  sample="$(probe_appconnect_ms "$SECONDARY_ENDPOINT")"
  if [ -n "$sample" ]; then
    secondary_samples+=("$sample")
  else
    secondary_failed=$((secondary_failed + 1))
  fi
done

primary_success=${#primary_samples[@]}
secondary_success=${#secondary_samples[@]}

if [ "$primary_attempts" -gt 0 ]; then
  primary_loss_pct=$(( (primary_failed * 100) / primary_attempts ))
else
  primary_loss_pct=100
fi

if [ "$secondary_attempts" -gt 0 ]; then
  secondary_loss_pct=$(( (secondary_failed * 100) / secondary_attempts ))
else
  secondary_loss_pct=100
fi

if [ "$primary_success" -gt 0 ]; then
  primary_sorted="$(printf '%s\n' "${primary_samples[@]}" | sort -n)"
  primary_median_ms="$(printf '%s\n' "$primary_sorted" | compute_median)"
  primary_p90_ms="$(printf '%s\n' "$primary_sorted" | compute_p90)"
  primary_jitter_ms=$((primary_p90_ms - primary_median_ms))
  if [ "$primary_jitter_ms" -lt 0 ]; then primary_jitter_ms=0; fi
else
  primary_median_ms=0
  primary_jitter_ms=0
fi

if [ "$secondary_success" -gt 0 ]; then
  secondary_sorted="$(printf '%s\n' "${secondary_samples[@]}" | sort -n)"
  secondary_median_ms="$(printf '%s\n' "$secondary_sorted" | compute_median)"
  secondary_p90_ms="$(printf '%s\n' "$secondary_sorted" | compute_p90)"
  secondary_jitter_ms=$((secondary_p90_ms - secondary_median_ms))
  if [ "$secondary_jitter_ms" -lt 0 ]; then secondary_jitter_ms=0; fi
else
  secondary_median_ms=0
  secondary_jitter_ms=0
fi

primary_median_ms="$(round_to_even "$primary_median_ms")"
primary_jitter_ms="$(round_to_even "$primary_jitter_ms")"
secondary_median_ms="$(round_to_even "$secondary_median_ms")"
secondary_jitter_ms="$(round_to_even "$secondary_jitter_ms")"

# Overall indicator color = worse stability between RU and OUT endpoints.
worst_loss="$primary_loss_pct"
worst_jitter="$primary_jitter_ms"
if [ "$secondary_loss_pct" -gt "$worst_loss" ]; then worst_loss="$secondary_loss_pct"; fi
if [ "$secondary_jitter_ms" -gt "$worst_jitter" ]; then worst_jitter="$secondary_jitter_ms"; fi

color="$(pick_color "$worst_loss" "$worst_jitter")"
config_base64="$(printf '{"renderingMode":"Palette", "colors":["%s"], "scale":"small", "weight":"ultralight"}' "$color" | base64)"

# Menu value = average median between RU and OUT.
if [ "$primary_success" -gt 0 ] && [ "$secondary_success" -gt 0 ]; then
  avg_median_ms=$(( (primary_median_ms + secondary_median_ms) / 2 ))
elif [ "$primary_success" -gt 0 ]; then
  avg_median_ms="$primary_median_ms"
elif [ "$secondary_success" -gt 0 ]; then
  avg_median_ms="$secondary_median_ms"
else
  avg_median_ms=0
fi
avg_median_ms="$(round_to_even "$avg_median_ms")"

# Keep width relatively stable with fixed 2-digit field.
menu_text="$(printf " %2dms" "$avg_median_ms")"
echo "${menu_text} | trim=false sfimage=circle.fill sfconfig=${config_base64}"
echo "---"
echo "${PRIMARY_ENDPOINT}"
echo "├ median: ${primary_median_ms}ms"
echo "├ jitter (p90-p50): ${primary_jitter_ms}ms"
echo "└ loss: ${primary_loss_pct}% out of ${primary_attempts} attempts"
echo ""
echo "${SECONDARY_ENDPOINT}"
echo "├ median: ${secondary_median_ms}ms"
echo "├ jitter (p90-p50): ${secondary_jitter_ms}ms"
echo "└ loss: ${secondary_loss_pct}% out of ${secondary_attempts} attempts"
