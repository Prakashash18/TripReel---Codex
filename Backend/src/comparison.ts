import type {
  AIEditComparison,
  AIEditPlanV3,
  FirstCutInput,
  PhotoInput,
} from "./contract.ts";

function longestIncreasingSubsequenceLength(values: readonly number[]): number {
  const tails: number[] = [];
  for (const value of values) {
    let low = 0;
    let high = tails.length;
    while (low < high) {
      const middle = Math.floor((low + high) / 2);
      if (tails[middle] < value) low = middle + 1;
      else high = middle;
    }
    tails[low] = value;
  }
  return tails.length;
}

function normalizedText(value: string): string {
  return value.replace(/\s+/gu, " ").trim().toLocaleLowerCase("en");
}

function baselineTitleSignature(baseline: FirstCutInput, kind: "opening" | "chapter" | "ending"): string {
  const title = baseline.titles.find((candidate) => candidate.kind === kind);
  if (title === undefined) return "";
  return [title.title, title.subtitle, title.style, title.durationSeconds.toFixed(2)]
    .map(normalizedText)
    .join("|");
}

function aiTitleSignatures(plan: AIEditPlanV3): Record<"opening" | "chapter" | "ending", string> {
  const chapterIsDistinct = plan.sequence.length >= 5 &&
    normalizedText(plan.story.title) !== normalizedText(plan.hook.title);
  return {
    opening: [plan.hook.title, plan.hook.subtitle, plan.hook.style, plan.hook.durationSeconds.toFixed(2)]
      .map(normalizedText).join("|"),
    chapter: chapterIsDistinct
      ? [plan.story.title, "", "clean", "1.60"].map(normalizedText).join("|")
      : "",
    ending: plan.ending.enabled
      ? [plan.ending.title, plan.ending.subtitle, plan.ending.style, plan.ending.durationSeconds.toFixed(2)]
        .map(normalizedText).join("|")
      : "",
  };
}

export function compareAICut(
  baseline: FirstCutInput,
  photos: readonly PhotoInput[],
  plan: AIEditPlanV3,
): AIEditComparison {
  const baselineByID = new Map(baseline.sequence.map((item) => [item.photoId, item]));
  const baselineIndex = new Map(baseline.sequence.map((item, index) => [item.photoId, index]));
  const photoByID = new Map(photos.map((photo) => [photo.id, photo]));
  const aiIDs = new Set(plan.sequence.map((item) => item.photoId));
  const commonSequence = plan.sequence
    .map((item) => baselineIndex.get(item.photoId))
    .filter((index): index is number => index !== undefined);

  const restoredCount = plan.sequence.filter(
    (item) => photoByID.get(item.photoId)?.localSelection === "more_photos",
  ).length;
  const removedCount = baseline.sequence.filter((item) => !aiIDs.has(item.photoId)).length;
  const reorderedCount = Math.max(
    0,
    commonSequence.length - longestIncreasingSubsequenceLength(commonSequence),
  );
  const retimedCount = plan.sequence.filter((item) => {
    const previous = baselineByID.get(item.photoId);
    return previous !== undefined && Math.abs(previous.durationSeconds - item.durationSeconds) >= 0.25;
  }).length;
  const motionChangedCount = plan.sequence.filter((item) => {
    const previous = baselineByID.get(item.photoId);
    return previous !== undefined && previous.motion !== item.motion;
  }).length;

  const aiTitles = aiTitleSignatures(plan);
  const titleChangedCount = (["opening", "chapter", "ending"] as const).filter(
    (kind) => baselineTitleSignature(baseline, kind) !== aiTitles[kind],
  ).length;
  const soundtrackChanged = baseline.soundtrackId !== plan.soundtrack.trackId;
  const treatmentChanged = baseline.look !== plan.treatment.look ||
    baseline.motionIntensity !== plan.treatment.motionIntensity;

  const submittedCount = Math.max(1, photos.length);
  const commonCount = Math.max(1, commonSequence.length);
  const score = Math.min(100, Math.round(
    Math.min(1, (restoredCount + removedCount) / submittedCount) * 35 +
    Math.min(1, reorderedCount / commonCount) * 20 +
    Math.min(1, retimedCount / commonCount) * 15 +
    Math.min(1, motionChangedCount / commonCount) * 10 +
    (titleChangedCount / 3) * 10 +
    (soundtrackChanged ? 5 : 0) +
    (treatmentChanged ? 5 : 0)
  ));
  const timelineChanges = restoredCount + removedCount + reorderedCount + retimedCount +
    motionChangedCount + titleChangedCount;
  const changedDimensions = [
    restoredCount + removedCount > 0,
    reorderedCount > 0,
    retimedCount > 0,
    motionChangedCount > 0,
    titleChangedCount > 0,
    soundtrackChanged,
    treatmentChanged,
  ].filter(Boolean).length;
  const minimumTimelineChanges = Math.max(3, Math.ceil(plan.sequence.length * 0.16));

  return {
    firstCutPhotoCount: baseline.photoCount,
    aiCutPhotoCount: plan.sequence.length,
    restoredCount,
    removedCount,
    reorderedCount,
    retimedCount,
    motionChangedCount,
    titleChangedCount,
    soundtrackChanged,
    treatmentChanged,
    score,
    materiallyDifferent: score >= 22 && changedDimensions >= 2 && timelineChanges >= minimumTimelineChanges,
  };
}

export function comparisonRevisionBrief(comparison: AIEditComparison): string {
  return [
    "The first draft is too similar to the submitted First Cut.",
    `Measured difference score: ${comparison.score}/100.`,
    `Restored ${comparison.restoredCount}; removed ${comparison.removedCount}; reordered ${comparison.reorderedCount}; retimed ${comparison.retimedCount}; changed motion ${comparison.motionChangedCount}; changed titles ${comparison.titleChangedCount}.`,
    "Revise the plan using visible evidence: address the diagnosed weaknesses, create a materially different sequence and rhythm, and avoid cosmetic-only changes.",
    "Do not make arbitrary changes solely to increase counts; every change must improve the requested direction.",
  ].join(" ");
}
