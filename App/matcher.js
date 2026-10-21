/* 中文稿件对齐实验核心。iOS JavaScriptCore 与 Node 测试使用同一文件。
   输入是识别器当前轮次的完整转写，不把每次部分结果当成新说的话。 */
(function (root) {
  'use strict';
  function normalize(text) {
    return Array.from(String(text).normalize('NFKC').toLowerCase())
      .filter(c => /[\p{L}\p{N}]/u.test(c)).join('');
  }
  function distance(a, b) {
    let row = Array.from({length: b.length + 1}, (_, i) => i);
    for (let i = 0; i < a.length; i++) {
      const next = [i + 1];
      for (let j = 0; j < b.length; j++) {
        next[j + 1] = Math.min(next[j] + 1, row[j + 1] + 1,
          row[j] + (a[i] === b[j] ? 0 : 1));
      }
      row = next;
    }
    return row[b.length];
  }
  class ScriptMatcher {
    constructor(script) {
      this.script = Array.from(normalize(script));
      this.position = 0;
      this.lastTranscript = '';
    }
    newUtterance() { this.lastTranscript = ''; }
    seek(position) {
      this.position = Math.max(0, Math.min(this.script.length, Math.round(position)));
      this.newUtterance();
      return this.position;
    }
    update(transcript) {
      const text = normalize(transcript);
      const result = (reason, confidence = 0) => ({position: this.position, reason, confidence});
      if (text === this.lastTranscript) return result('unchanged');
      const previousLength = Array.from(this.lastTranscript).length;
      this.lastTranscript = text;
      const heard = Array.from(text).slice(-12);
      if (heard.length < 3) return result('insufficient-evidence');
      const candidates = [];
      for (let end = 1; end <= this.script.length; end++) {
        let best = 0;
        for (let len = Math.max(3, heard.length - 2); len <= heard.length + 2; len++) {
          if (len > end) continue;
          const candidate = this.script.slice(end - len, end);
          const score = 1 - distance(heard, candidate) / Math.max(heard.length, len);
          best = Math.max(best, score);
        }
        if (best >= 0.70) candidates.push({end, score: best});
      }
      candidates.sort((a, b) => b.score - a.score ||
        Math.abs(a.end - this.position) - Math.abs(b.end - this.position));
      if (!candidates.length) return result('no-match');
      // Merge adjacent endpoints of one fuzzy match, not separate repeated phrases.
      const groups = [];
      for (const candidate of candidates) {
        if (!groups.some(g => Math.abs(g.end - candidate.end) <= 2)) groups.push(candidate);
      }
      let best = groups[0];
      const competing = groups.filter(c => best.score - c.score < 0.12);
      if (competing.length > 1) {
        const advance = Math.max(3, Array.from(text).length - previousLength);
        const nearby = competing.filter(c => c.end >= this.position &&
          c.end - this.position <= advance + 1);
        if (nearby.length !== 1) return result('ambiguous', best.score);
        best = nearby[0];
      }
      const delta = best.end - this.position;
      if ((delta < -3 || delta > 24) && (heard.length < 6 || best.score < 0.84)) {
        return result('jump-needs-more-evidence', best.score);
      }
      if (best.score < 0.76 || (heard.length < 5 && best.score < 1)) {
        return result('low-confidence', best.score);
      }
      this.position = best.end;
      return result(delta < 0 ? 'backtrack' : delta > 24 ? 'jump' : 'follow', best.score);
    }
  }
  root.ScriptMatcher = ScriptMatcher;
  root.normalizeScript = normalize;
  if (typeof module !== 'undefined') module.exports = {ScriptMatcher, normalize, distance};
})(typeof globalThis !== 'undefined' ? globalThis : this);
