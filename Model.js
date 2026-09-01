.pragma library

var WEEK_MS = 7 * 24 * 60 * 60 * 1000

// USD per 1M tokens: API-equivalent reference rates, not subscription charges.
var MODEL_PRICES = {
  "gpt-5.6-luna": { input: 0.20, cached: 0.02, output: 1.20 },
  "gpt-5.6-sol": { input: 4.00, cached: 0.40, output: 20.00 },
  "gpt-5.6-terra": { input: 2.00, cached: 0.20, output: 12.00 },
  "gpt-5.5": { input: 5.00, cached: 0.50, output: 30.00 },
  "codex-auto-review": { input: 2.50, cached: 0.25, output: 15.00 }
}

function number(value, fallback) {
  var parsed = Number(value)
  return isFinite(parsed) ? parsed : fallback
}

function friendlyModelName(value) {
  return String(value || "Model").replace(/[-_]+/g, " ").replace(/\b\w/g, function(letter) { return letter.toUpperCase() })
}

function estimateApiCost(bucket, modelId) {
  var price = MODEL_PRICES[String(modelId || "")]
  if (!price || !bucket) return null
  var input = Math.max(0, number(bucket.inputTokens, 0))
  var cached = Math.max(0, number(bucket.cacheReadInputTokens, 0))
  var writes = Math.max(0, number(bucket.cacheCreationInputTokens, 0))
  var output = Math.max(0, number(bucket.outputTokens, 0))
  return (input * price.input + cached * price.cached + writes * price.input * 1.25 + output * price.output) / 1000000
}

function clamp(value, minimum, maximum) {
  return Math.max(minimum, Math.min(maximum, value))
}

function findWeekly(limits) {
  var list = Array.isArray(limits) ? limits : []
  for (var i = 0; i < list.length; i++) {
    var label = String(list[i].label || "").toLowerCase()
    if (label.indexOf("weekly") === 0 && label.indexOf("7-day") >= 0) return list[i]
  }
  for (var j = 0; j < list.length; j++) {
    var fallbackLabel = String(list[j].label || "").toLowerCase()
    if (fallbackLabel.indexOf("weekly") === 0) return list[j]
  }
  return null
}

function normalizeLimit(limit, nowMs) {
  if (!limit) return null
  var used = clamp(number(limit.percent, 0), 0, 1)
  var resetMs = Date.parse(String(limit.resetsAt || ""))
  if (!isFinite(resetMs)) resetMs = 0
  var remaining = 1 - used
  var timeRemaining = resetMs > 0 ? Math.max(0, resetMs - nowMs) : 0
  return {
    label: String(limit.title || limit.label || "Limit"),
    used: used,
    remaining: remaining,
    resetMs: resetMs,
    timeRemainingMs: timeRemaining
  }
}

function parseProvider(stdout, providerId, nowMs) {
  try {
    var raw = JSON.parse(String(stdout || ""))
    var limits = Array.isArray(raw.limits) ? raw.limits : []
    var weekly = normalizeLimit(findWeekly(limits), nowMs)
    var normalized = []
    for (var i = 0; i < limits.length; i++) {
      var item = normalizeLimit(limits[i], nowMs)
      if (item) normalized.push(item)
    }
    return {
      ok: true,
      provider: {
        id: String(providerId || raw.id || ""),
        name: String(raw.name || providerId || ""),
        plan: String(raw.plan || raw.tierLabel || ""),
        status: String(raw.usageStatusText || ""),
        weekly: weekly,
        limits: normalized,
        modelUsage: raw.modelUsage || {},
        modelUsage: raw.modelUsage || {},
        recentDays: Array.isArray(raw.recentDays) ? raw.recentDays : [],
        updatedAt: String(raw.updatedAt || "")
      }
    }
  } catch (error) {
    return { ok: false, error: "Could not parse " + providerId + " usage" }
  }
}

function expectedRemaining(weekly, nowMs) {
  if (!weekly || weekly.resetMs <= 0) return 0
  return clamp((weekly.resetMs - nowMs) / WEEK_MS, 0, 1)
}

function behindPace(weekly, nowMs) {
  if (!weekly || weekly.resetMs <= 0) return false
  return weekly.remaining + 0.0005 < expectedRemaining(weekly, nowMs)
}

function paceDifference(weekly, nowMs) {
  if (!weekly) return 0
  return weekly.remaining - expectedRemaining(weekly, nowMs)
}

function percent(value) {
  return Math.round(clamp(number(value, 0), 0, 1) * 100) + "%"
}

function countdown(resetMs, nowMs) {
  if (!resetMs || resetMs <= nowMs) return "now"
  var minutes = Math.max(0, Math.floor((resetMs - nowMs) / 60000))
  var days = Math.floor(minutes / 1440)
  var hours = Math.floor((minutes % 1440) / 60)
  var mins = minutes % 60
  if (days > 0) return days + "d " + hours + "h"
  if (hours > 0) return hours + "h " + mins + "m"
  return mins + "m"
}

function paceText(weekly, nowMs) {
  if (!weekly) return "No weekly limit"
  var points = Math.round(Math.abs(paceDifference(weekly, nowMs)) * 100)
  if (points === 0) return "On pace"
  return points + "% " + (behindPace(weekly, nowMs) ? "behind pace" : "ahead of pace")
}

function dayTokens(day) {
  return Math.max(0, number(day ? day.messageCount : 0, 0))
}

function recentTotal(days) {
  var list = Array.isArray(days) ? days : []
  var total = 0
  for (var i = 0; i < list.length; i++) total += dayTokens(list[i])
  return total
}

function recentPeak(days) {
  var list = Array.isArray(days) ? days : []
  var peak = 0
  for (var i = 0; i < list.length; i++) peak = Math.max(peak, dayTokens(list[i]))
  return peak
}

function tokenCount(value) {
  var amount = Math.max(0, number(value, 0))
  if (amount >= 1000000000) return (amount / 1000000000).toFixed(amount >= 10000000000 ? 0 : 1).replace(/\.0$/, "") + "B"
  if (amount >= 1000000) return (amount / 1000000).toFixed(amount >= 100000000 ? 0 : 1).replace(/\.0$/, "") + "M"
  if (amount >= 1000) return (amount / 1000).toFixed(amount >= 100000 ? 0 : 1).replace(/\.0$/, "") + "K"
  return String(Math.round(amount))
}

function dayLabel(value) {
  var match = /^(\d{4})-(\d{2})-(\d{2})$/.exec(String(value || ""))
  if (!match) return "—"
  var date = new Date(Number(match[1]), Number(match[2]) - 1, Number(match[3]))
  return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][date.getDay()]
}

var exportsObject = {
  WEEK_MS: WEEK_MS,
  findWeekly: findWeekly,
  normalizeLimit: normalizeLimit,
  parseProvider: parseProvider,
  expectedRemaining: expectedRemaining,
  behindPace: behindPace,
  paceDifference: paceDifference,
  percent: percent,
  countdown: countdown,
  paceText: paceText,
  dayTokens: dayTokens,
  recentTotal: recentTotal,
  recentPeak: recentPeak,
  tokenCount: tokenCount,
  dayLabel: dayLabel,
  friendlyModelName: friendlyModelName,
  estimateApiCost: estimateApiCost
}

if (typeof module !== "undefined" && module.exports) module.exports = exportsObject
