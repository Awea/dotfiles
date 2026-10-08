import re, sys, json, glob, os

# Score v2: adds complex_tense (perfect tenses, modal stacks), exempts
# adjectival/stative participles from the passive count, moves "provide" to the
# banned list, adds a noun-train marker and a --strict mode. The episode's
# published numbers were measured with score v1 (this file's git history at the
# episode date); v1 and v2 totals are close but not directly comparable.
SCORE_VERSION = 2

# Shape v1: the Layer 2 checks (skill 2.0). These count the ORDER of a reply to
# a person, not the words. They are reported apart from the score and never
# enter `total`, so `total_per100w` keeps one meaning across skill versions.
SHAPE_VERSION = 1

MARKETING = ["seamless","seamlessly","robust","powerful","cutting-edge","effortless","effortlessly",
    "world-class","next-generation","revolutionary","blazing","lightning-fast","elegant","delightful",
    "turnkey","best-in-class","state-of-the-art","game-changing","first-class","battle-tested",
    "enterprise-grade","supercharge","unlock","unleash","empower","empowers"]
BANNED = ["begin","begins","commence","commences","initiate","initiates","originate",
    "utilize","utilizes","utilizing","leverage","leverages","leveraging","facilitate","facilitates",
    "ensure","ensures","ensuring","prior to","subsequent to","obtain","obtains","acquire","acquires",
    "demonstrate","demonstrates","additionally","furthermore","moreover","comprehensive","comprehensively",
    "utilization","aforementioned","henceforth","therein","whilst","amongst","numerous","myriad","plethora",
    "provide","provides","provided",
    "in order to","a variety of","in the event that","due to the fact that","it is important to note"]
# STE's own recurring-errors list (see ste-recurring-errors.md). Counted only
# with --strict: these are correct STE but would flag normal prose in docs.
STRICT_BANNED = ["however","since","should","shall","using","follow","follows","followed"]
PHRASAL = ["spin up","spin down","reach out","dive into","dives into","diving into","kick off","kicks off",
    "roll out","rolls out","tear down","ramp up","circle back","drill down","spun up","reaching out"]
MODAL_HEDGE = ["it is important to note","it should be noted","it is worth noting","please note that",
    "as mentioned","as noted above"]
BE = r"(?:am|is|are|was|were|be|been|being)"
PP_IRREG = r"(?:done|made|sent|read|built|kept|held|set|put|run|written|shown|given|taken|found|got|gotten|seen|known|thrown|drawn)"
# Rule 3.3: a past participle used as an adjective is not passive. These
# stative participles only count as passive when a by-agent follows.
STATIVE = r"(?:closed|opened?|damaged|completed?|installed|connected|required|expected|configured|enabled|disabled|deprecated|supported)"
FUNC_WORDS = set("""a an the this that these those of for to in on at by with from as and or but if
when then than not no is are was were be been being am do does did has have had will would can could
may might must should shall it its their your our his her they we you i""".split())

# --- Layer 2 (shape) word lists -------------------------------------------
# An opener is counted in the first sentence only. Everything else is counted
# over the whole text.
OPENERS = ["great question","good question","let me","i'll","i will","sure","certainly",
    "absolutely","looking at your","to answer your question","happy to help",
    "i'd be happy to","that's a great","first,","alright","okay so","let's"]
CLOSERS = ["let me know if","hope this helps","hope that helps","happy to clarify",
    "feel free to ask","feel free to reach","anything else","if you have any questions",
    "if you have any other questions","i'm here to help","do not hesitate","don't hesitate"]
RECAP = ["to summarize","in summary","to recap","as a recap","in conclusion","to sum up",
    "i have now","i've now","overall,"]
# Only hedges that carry no fact. A qualifier that bounds a claim is not here.
HEDGE = ["perhaps","arguably","presumably","conceivably","ostensibly","somewhat",
    "kind of","sort of","more or less","it seems that","it appears that","fairly straightforward"]
VAGUE = ["some work","a bit of work","a while","shortly","fairly soon","a few moments",
    "not too long","some time","in no time","quite quick","pretty quick"]
SOFTENER = ["uh oh","oh no","there seems to be a problem","there seems to be an issue",
    "unfortunately","i apologize","apologies","my apologies","sorry about that"]

def strip_code(t):
    t = re.sub(r"```.*?```", " ", t, flags=re.S)
    t = re.sub(r"`[^`]*`", " ", t)
    return t

def sentences(text):
    out = []
    for line in text.split("\n"):
        s = line.strip()
        if not s: continue
        s = re.sub(r"^\s*#{1,6}\s*", "", s)
        s = re.sub(r"^\s*(?:[-*+]|\d+[.)])\s+", "", s)
        if not s: continue
        parts = re.split(r"(?<=[.!?:])\s+(?=[A-Z0-9\"'\-])", s)
        for p in parts:
            p = p.strip()
            if p: out.append(p)
    return out

def wc(s):
    return len([w for w in re.findall(r"[A-Za-z0-9][A-Za-z0-9'\-/]*", s)])

def count_ci(text, phrases):
    n = 0; hits = []
    low = text.lower()
    for ph in phrases:
        for m in re.finditer(r"(?<![a-z])" + re.escape(ph) + r"(?![a-z])", low):
            n += 1; hits.append(ph)
    return n, hits

def noun_trains(text):
    """Runs of 4+ consecutive non-function lowercase words (Rule 2.1 proxy).
    Heuristic marker only - proper nouns break a run, the leading word of each
    sentence is skipped, and the count stays out of the total."""
    hits = []
    for s in sentences(text):
        words = re.findall(r"[A-Za-z][A-Za-z'\-]*", s)[1:]
        run = []
        for w in words + [""]:
            if w and w.lower() not in FUNC_WORDS and not w[0].isupper():
                run.append(w)
            else:
                if len(run) >= 4: hits.append(" ".join(run))
                run = []
    return hits

def count_in(fragment, phrases):
    """Presence count over one fragment - each phrase counts at most one time."""
    low = fragment.lower().replace("’", "'")
    n = 0; hits = []
    for ph in phrases:
        if re.search(r"(?<![a-z])" + re.escape(ph) + r"(?![a-z])", low):
            n += 1; hits.append(ph)
    return n, hits


def long_lists(raw):
    """Runs of more than five consecutive list items (Layer 2 cap). A table row
    starts with a pipe, so a reference table never counts."""
    n = 0; run = 0
    for line in raw.split("\n"):
        if re.match(r"^\s*(?:[-*+]|\d+[.)])\s+", line):
            run += 1
        elif not line.strip():
            continue
        else:
            if run > 5: n += 1
            run = 0
    if run > 5: n += 1
    return n


def shape(raw):
    """Layer 2 counts. Applies to a reply to a person, not to a reference doc."""
    text = strip_code(raw).replace("’", "'")
    sents = sentences(text)
    s = {}
    s["preamble_opener"] = count_in(sents[0], OPENERS)[0] if sents else 0
    s["closer"], ch = count_ci(text, CLOSERS)
    s["recap_marker"], rh = count_ci(text, RECAP)
    s["hedge"], hh = count_ci(text, HEDGE)
    s["vague_estimate"], vh = count_ci(text, VAGUE)
    s["error_softener"], sh = count_ci(text, SOFTENER)
    s["action_list(>5)"] = long_lists(re.sub(r"```.*?```", "\n", raw, flags=re.S))
    return s, list(dict.fromkeys(ch + rh + hh + vh + sh))[:6]


def lint(text, strict=False):
    raw = text
    text = strip_code(text)
    sents = sentences(text)
    words = sum(wc(s) for s in sents) or 1
    v = {}
    longs = [(wc(s), s) for s in sents if wc(s) > 20]
    v["long_sentence(>20w)"] = len(longs)
    v["semicolon"] = text.count(";")
    v["contraction"] = len(re.findall(r"\b\w+['’](?:t|re|ve|ll|d|s|m)\b", text))
    passive_parts = re.findall(rf"\b{BE}\s+(\w+ed|{PP_IRREG})\b", text, re.I)
    v["passive_voice"] = sum(1 for p in passive_parts if not re.fullmatch(STATIVE, p, re.I)) \
        + len(re.findall(rf"\b{BE}\s+{STATIVE}\s+by\b", text, re.I))
    v["complex_tense"] = len(re.findall(
        rf"\b(?:(?:may|might|could|would|should|must|will|shall|can)\s+)?(?:have|has|had)\s+(?:been\s+)?(?:\w+ed|{PP_IRREG})\b",
        text, re.I))
    v["ing_main_verb"] = len(re.findall(rf"\b{BE}\s+\w+ing\b", text, re.I))
    v["nominalization"] = len(re.findall(r"\b(?:perform(?:s|ed)?|conduct(?:s|ed)?|carry out|carries out|make use of|makes use of)\b", text, re.I)) + len(re.findall(r"\b\w{4,}(?:tion|ment|ance|ence)\s+of\b", text, re.I))
    v["phrasal_verb"], _ = count_ci(text, PHRASAL)
    v["banned_word"], bh = count_ci(text, BANNED)
    v["marketing_adjective"], mh = count_ci(text, MARKETING)
    v["modal_hedge"], _ = count_ci(text, MODAL_HEDGE)
    paras = [p for p in re.split(r"\n\s*\n", raw) if p.strip()]
    v["long_paragraph(>6s)"] = sum(1 for p in paras if len(sentences(strip_code(p))) > 6)
    em = raw.count("—") + raw.count("–")
    trains = noun_trains(text)
    if strict:
        n_strict, sh = count_ci(text, STRICT_BANNED)
        # "may" is matched case-sensitively so the month "May" stays clean
        n_strict += len(re.findall(r"(?<![A-Za-z])may(?![a-z])", text))
        v["strict_banned_word"] = n_strict
        v["em_dash"] = em
    total = sum(v.values())
    sh, sh_samples = shape(raw)
    return {
        "score_version": SCORE_VERSION,
        "shape_version": SHAPE_VERSION,
        "mode": "strict" if strict else "flavored",
        "words": words, "sentences": len(sents),
        "violations": v, "total": total,
        "total_per100w": round(total*100.0/words, 2),
        "shape": sh, "shape_total": sum(sh.values()),
        "sample_shape": sh_samples,
        "em_dash(slop-marker)": em,
        "noun_train(>=4w,marker)": len(trains),
        "longest_sentence_words": (max(longs)[0] if longs else max((wc(s) for s in sents), default=0)),
        "sample_marketing": list(dict.fromkeys(mh))[:6],
        "sample_banned": list(dict.fromkeys(bh))[:6],
        "sample_noun_train": trains[:3],
    }

if __name__ == "__main__":
    args = sys.argv[1:]
    strict = "--strict" in args
    as_json = "--json" in args
    show_shape = "--shape" in args
    fail_over = None
    fail_shape = None
    for flag in ("--fail-over", "--fail-shape"):
        if flag in args:
            i = args.index(flag)
            value = float(args[i + 1])
            if flag == "--fail-over": fail_over = value
            else: fail_shape = value
            del args[i:i + 2]
    files = [a for a in args if a not in ("--strict", "--json", "--shape")]
    worst = 0.0
    worst_shape = 0
    if not files:
        sys.stdin.reconfigure(encoding="utf-8")
        r = lint(sys.stdin.read(), strict=strict)
        print(json.dumps(r, indent=2))
        worst = r["total_per100w"]
        worst_shape = r["shape_total"]
    else:
        exp = []
        for f in files: exp += sorted(glob.glob(f)) if any(c in f for c in "*?[") else [f]
        for f in exp:
            with open(f, encoding="utf-8") as fh: r = lint(fh.read(), strict=strict)
            worst = max(worst, r["total_per100w"])
            worst_shape = max(worst_shape, r["shape_total"])
            if as_json:
                print(json.dumps({"file": f, **r}, indent=2))
            else:
                tail = f" shape={r['shape_total']:2d}" if show_shape else ""
                print(f"{os.path.basename(f):32} words={r['words']:4d} total={r['total']:3d} per100w={r['total_per100w']:6.2f} em_dash={r['em_dash(slop-marker)']:2d}{tail}")
    if fail_over is not None and worst > fail_over:
        sys.exit(1)
    if fail_shape is not None and worst_shape > fail_shape:
        sys.exit(1)
