#!/usr/bin/env bash
#
# The action's whole body. Kept out of action.yml so it can be run and read on
# a laptop, which a `run:` block folded into YAML cannot.
#
# The rule the rest of the project is built around applies here unchanged: a
# name is available only when a registry said so. `status` alone is not enough —
# an estimate carries `confidence: estimated`, and treating that as availability
# is the one wrong answer that costs somebody money.

set -euo pipefail

API="${INPUT_API:-https://dotsweep.com}"
API="${API%/}"
BATCH=10   # MAX_BATCH on the server; a larger request is rejected, not split.

# One definition of the verdict, reused by the outputs and by the summary table,
# so the number in the log can never disagree with the row in the table.
#
# `closed` is tested first and outranks the rest. A .brand TLD answers RDAP with
# a genuine not-found, so `status` alone reports `shoes.nike` as free — true, and
# useless, because nobody outside Nike may buy it. Availability here means
# registrable, not merely unregistered.
VERDICT='def verdict:
  if (.policy.closed // false) then "closed"
  elif .status == "available" and .confidence == "certain" then "available"
  elif .status == "taken" and .confidence == "certain" then "taken"
  else "unconfirmed" end;'

expand() {
  local raw="${INPUT_DOMAINS:-}" tlds="${INPUT_TLDS:-}" name tld
  raw="$(printf '%s' "$raw" | tr ',;\n\r\t' '     ')"
  tlds="$(printf '%s' "$tlds" | tr ',;\n\r\t' '     ')"
  for name in $raw; do
    if [ -z "$tlds" ]; then
      printf '%s\n' "$name"
    else
      for tld in $tlds; do printf '%s\n' "${name%.}.${tld#.}"; done
    fi
  done
}

# A transient failure must never look like an answer. Three tries, then the step
# fails — dropping the batch would silently shrink the result set, and a name
# missing from `taken` reads exactly like a name that is free.
post_batch() {
  local payload="$1" attempt=1 body status
  while :; do
    body="$(curl -sS -m 45 -w '\n%{http_code}' \
      -X POST "$API/check" \
      -H 'content-type: application/json' \
      -H 'user-agent: dotsweep-action (+https://github.com/stanmaygo/dotsweep)' \
      -d "$payload" 2>&1)" || body=""
    status="$(printf '%s' "$body" | tail -n1)"
    if [ "$status" = "200" ]; then
      printf '%s' "$body" | sed '$d'
      return 0
    fi
    if [ "$attempt" -ge 3 ]; then
      echo "::error::dotsweep API returned ${status:-no response} after $attempt attempts" >&2
      return 1
    fi
    sleep $((attempt * 3))
    attempt=$((attempt + 1))
  done
}

# Unquoted on purpose: splits on spaces and newlines alike, so it counts both a
# newline-separated domain list and a space-separated output line.
count() { set -- $1; echo $#; }

domains="$(expand | awk 'NF' | awk '!seen[$0]++')"
if [ -z "$domains" ]; then
  echo "::error::no domains to check" >&2
  exit 1
fi

acc="$(mktemp)"
trap 'rm -f "$acc"' EXIT

while IFS= read -r batch; do
  [ -n "$batch" ] || continue
  payload="$(printf '%s\n' $batch | jq -R . | jq -sc '{domains: .}')"
  post_batch "$payload" | jq -c '.results[]' >>"$acc"
done < <(printf '%s\n' "$domains" | xargs -n "$BATCH")

results="$(jq -sc '.' "$acc")"

names() {
  printf '%s' "$results" | jq -r --arg want "$1" "$VERDICT"' .[] | select(verdict == $want) | .domain' \
    | paste -sd' ' -
}

available="$(names available)"
taken="$(names taken)"
closed="$(names closed)"
unconfirmed="$(names unconfirmed)"

{
  echo "results<<DOTSWEEP_EOF"
  echo "$results"
  echo "DOTSWEEP_EOF"
  echo "available=$available"
  echo "taken=$taken"
  echo "closed=$closed"
  echo "unconfirmed=$unconfirmed"
  echo "available-count=$(count "$available")"
  echo "taken-count=$(count "$taken")"
  echo "closed-count=$(count "$closed")"
  echo "unconfirmed-count=$(count "$unconfirmed")"
} >>"$GITHUB_OUTPUT"

# The last column carries refusals only. A technical obligation blocks nobody at
# the till, and `.app` and `.dev` are common enough that surfacing one here would
# mark almost every run — which teaches the reader to skip the ones that matter.
if [ "${INPUT_SUMMARY:-true}" = "true" ] && [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Domain availability"
    echo
    echo "| Domain | Verdict | First payment | Renewal / yr | Must qualify |"
    echo "| --- | --- | --- | --- | --- |"
    printf '%s' "$results" | jq -r "$VERDICT"'
      .[]
      | (if .price then "\(.price.currency) \(.price.first_payment)" else "—" end) as $first
      | (if .price then "\(.price.currency) \(.price.renewal)" else "—" end) as $renew
      | ([(if .policy.closed then .policy.closed_reason else null end), .policy.eligibility, .note]
         | map(select(. != null and . != "")) | first // "") as $note
      | "| `\(.domain)` | \(verdict) | \($first) | \($renew) | \($note | gsub("[|\n]"; " ") | .[0:100]) |"
    '
    echo
    echo "_An unconfirmed name is not an available one — no registry would answer for it._"
  } >>"$GITHUB_STEP_SUMMARY"
fi

fail=""
if [ "${INPUT_FAIL_IF_AVAILABLE:-false}" = "true" ] && [ -n "$available" ]; then
  fail="available: $available"
fi
if [ "${INPUT_FAIL_IF_TAKEN:-false}" = "true" ] && [ -n "$taken" ]; then
  fail="${fail:+$fail; }taken: $taken"
fi
if [ "${INPUT_FAIL_IF_UNCONFIRMED:-false}" = "true" ] && [ -n "$unconfirmed" ]; then
  fail="${fail:+$fail; }unconfirmed: $unconfirmed"
fi

if [ -n "$fail" ]; then
  echo "::error::$fail" >&2
  exit 1
fi

echo "checked $(count "$domains") name(s): $(count "$available") available, $(count "$taken") taken, $(count "$closed") closed, $(count "$unconfirmed") unconfirmed"
