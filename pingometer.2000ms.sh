# <xbar.title>Pingometer</xbar.title>
# <xbar.version>v1.3</xbar.version>
# <xbar.author>ymatuhin</xbar.author>
# <xbar.github>ymatuhin</xbar.github>
# <xbar.desc>Show RU vs outside connection stability (median/jitter/loss)</xbar.desc>
# <xbar.about>https://ymatuhin.ru</xbar.about>
# <xbar.dependencies>curl</xbar.dependencies>
# <swiftbar.hideRunInTerminal>true</swiftbar.hideRunInTerminal>
# <swiftbar.hideLastUpdated>true</swiftbar.hideLastUpdated>
# <swiftbar.hideDisablePlugin>true</swiftbar.hideDisablePlugin>
# <swiftbar.hideAbout>true</swiftbar.hideAbout>

RU_ENDPOINT="https://ya.ru/favicon.ico"
OUT_ENDPOINT="https://gstatic.com/generate_204"
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
  elif [ "$loss" -gt 20 ] || [ "$jitter" -gt 70 ]; then
    echo "$ORANGE"
  elif [ "$loss" -gt 0 ] || [ "$jitter" -gt 35 ]; then
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

ru_samples=()
out_samples=()
ru_attempts=0
ru_failed=0
out_attempts=0
out_failed=0

start_ms="$(now_ms)"
deadline_ms=$((start_ms + TOTAL_BUDGET_MS))

# Alternate RU and OUT probes until the 1.9s budget is exhausted.
while :; do
  current_ms="$(now_ms)"
  if [ "$current_ms" -ge "$deadline_ms" ]; then
    break
  fi

  ru_attempts=$((ru_attempts + 1))
  sample="$(probe_appconnect_ms "$RU_ENDPOINT")"
  if [ -n "$sample" ]; then
    ru_samples+=("$sample")
  else
    ru_failed=$((ru_failed + 1))
  fi

  current_ms="$(now_ms)"
  if [ "$current_ms" -ge "$deadline_ms" ]; then
    break
  fi

  out_attempts=$((out_attempts + 1))
  sample="$(probe_appconnect_ms "$OUT_ENDPOINT")"
  if [ -n "$sample" ]; then
    out_samples+=("$sample")
  else
    out_failed=$((out_failed + 1))
  fi
done

ru_success=${#ru_samples[@]}
out_success=${#out_samples[@]}

if [ "$ru_attempts" -gt 0 ]; then
  ru_loss_pct=$(( (ru_failed * 100) / ru_attempts ))
else
  ru_loss_pct=100
fi

if [ "$out_attempts" -gt 0 ]; then
  out_loss_pct=$(( (out_failed * 100) / out_attempts ))
else
  out_loss_pct=100
fi

if [ "$ru_success" -gt 0 ]; then
  ru_sorted="$(printf '%s\n' "${ru_samples[@]}" | sort -n)"
  ru_median_ms="$(printf '%s\n' "$ru_sorted" | compute_median)"
  ru_p90_ms="$(printf '%s\n' "$ru_sorted" | compute_p90)"
  ru_jitter_ms=$((ru_p90_ms - ru_median_ms))
  if [ "$ru_jitter_ms" -lt 0 ]; then ru_jitter_ms=0; fi
else
  ru_median_ms=0
  ru_jitter_ms=0
fi

if [ "$out_success" -gt 0 ]; then
  out_sorted="$(printf '%s\n' "${out_samples[@]}" | sort -n)"
  out_median_ms="$(printf '%s\n' "$out_sorted" | compute_median)"
  out_p90_ms="$(printf '%s\n' "$out_sorted" | compute_p90)"
  out_jitter_ms=$((out_p90_ms - out_median_ms))
  if [ "$out_jitter_ms" -lt 0 ]; then out_jitter_ms=0; fi
else
  out_median_ms=0
  out_jitter_ms=0
fi

ru_median_ms="$(round_to_even "$ru_median_ms")"
ru_jitter_ms="$(round_to_even "$ru_jitter_ms")"
out_median_ms="$(round_to_even "$out_median_ms")"
out_jitter_ms="$(round_to_even "$out_jitter_ms")"

# Overall indicator color = worse stability between RU and OUT endpoints.
worst_loss="$ru_loss_pct"
worst_jitter="$ru_jitter_ms"
if [ "$out_loss_pct" -gt "$worst_loss" ]; then worst_loss="$out_loss_pct"; fi
if [ "$out_jitter_ms" -gt "$worst_jitter" ]; then worst_jitter="$out_jitter_ms"; fi

color="$(pick_color "$worst_loss" "$worst_jitter")"
config_base64="$(printf '{"renderingMode":"Palette", "colors":["%s"], "scale":"small", "weight":"ultralight"}' "$color" | base64)"

# Menu value = average median between RU and OUT.
if [ "$ru_success" -gt 0 ] && [ "$out_success" -gt 0 ]; then
  avg_median_ms=$(( (ru_median_ms + out_median_ms) / 2 ))
elif [ "$ru_success" -gt 0 ]; then
  avg_median_ms="$ru_median_ms"
elif [ "$out_success" -gt 0 ]; then
  avg_median_ms="$out_median_ms"
else
  avg_median_ms=0
fi
avg_median_ms="$(round_to_even "$avg_median_ms")"

# Keep width relatively stable with fixed 2-digit field.
menu_text="$(printf " %2dms" "$avg_median_ms")"
echo "${menu_text} | trim=false sfimage=circle.fill sfconfig=${config_base64}"
echo "---"
echo "${RU_ENDPOINT}"
echo "├ median: ${ru_median_ms}ms"
echo "├ jitter (p90-p50): ${ru_jitter_ms}ms"
echo "└ loss: ${ru_loss_pct}% out of ${ru_attempts} attempts"
echo ""
echo "${OUT_ENDPOINT}"
echo "├ median: ${out_median_ms}ms"
echo "├ jitter (p90-p50): ${out_jitter_ms}ms"
echo "└ loss: ${out_loss_pct}% out of ${out_attempts} attempts"
