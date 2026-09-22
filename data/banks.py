"""Normalisation of the messy bank names found in OSM and bank websites.

OSM contributors type whatever they like into `operator`, so the same bank shows
up as "Cihan Bank", "Cihan Bank ATM", and inside multi-operator strings like
"Cihan(1), RT(2), NBI(1)" - and just as often in Arabic or Sorani. Everything
funnels through `normalise()`.

Each entry carries display names in all three of the app's languages. Arabic is
not optional: without it every Arabic-speaking user reads English bank names,
because the app falls back to English whenever a Kurdish name is missing.

NBI and TBI carry their initials in the display name because that is what people
in the region call them, and what is written on the machines. The parentheses
are plain characters with no bidi control marks - `(` and `)` are mirrored and
resolve as a matched pair under the bidi rules, so they render correctly inside
right-to-left text without help.

Two things this deliberately does NOT do:

* It does not guess a brand from a place name. Kurdish mappers very often label
  a branch after its neighbourhood ("Zanko Bank", "Bnaslawa Bank", "Tanjaro
  Bank"). Those are locations, not banks, so they stay unidentified and are a
  job for crowd verification.
* It does not treat card agents as banks. Qi Card outlets and FastPay agents
  handle salary cards but cannot dispense cash from a machine, so `kind()`
  separates them out.
"""

import re

# canonical id -> (english, sorani, arabic, match patterns)
BANKS = {
    "cihan": ("Cihan Bank", "بانکی جیهان", "مصرف جيهان",
              [r"cihan", r"جیهان", r"جيهان"]),
    "rt": ("RT Bank", "بانکی ئاڕ تی", "مصرف ريجن للتجارة",
           [r"\brtb?\b", r"region\s*trade", r"ئاڕ ?تی"]),
    "nbi": ("National Bank of Iraq (NBI)", "بانکی نیشتمانی عێراق (NBI)",
            "المصرف الأهلي العراقي (NBI)",
            [r"\bnbi\b", r"national bank of iraq", r"المصرف الأهلي العراقي",
             r"الاهلي العراقي"]),
    "tbi": ("Trade Bank of Iraq (TBI)", "بانکی بازرگانی عێراق (TBI)",
            "المصرف العراقي للتجارة (TBI)",
            [r"\btbi\b", r"trade bank of iraq", r"العراقي للتجارة"]),
    "baghdad": ("Bank of Baghdad", "بانکی بەغدا", "مصرف بغداد",
                [r"bank of baghdad", r"baghdad bank", r"مصرف بغداد", r"بەغدا"]),
    "kiib": ("Kurdistan International Islamic Bank",
             "بانکی نێودەوڵەتی ئیسلامی کوردستان",
             "مصرف كوردستان الدولي الإسلامي",
             [r"kurdistan international", r"كوردستان الدولي",
              r"نێودەوڵەتی ئیسلامی"]),
    "iib": ("Iraqi Islamic Bank", "بانکی ئیسلامی عێراقی",
            "المصرف العراقي الإسلامي",
            [r"iraqi islamic", r"المصرف العراقي الاسلامي", r"العراقي الإسلامي"]),
    "rasheed": ("Al-Rasheed Bank", "بانکی ڕەشید", "مصرف الرشيد",
                [r"rasheed", r"rashid", r"الرشيد"]),
    "rafidain": ("Al-Rafidain Bank", "بانکی ڕافیدەین", "مصرف الرافدين",
                 [r"rafidain", r"الرافدين"]),
    "mansour": ("Al-Mansour Bank", "بانکی مەنسوور", "مصرف المنصور",
                [r"mansou?r", r"المنصور"]),
    "north": ("North Bank", "بانکی باکوور", "مصرف الشمال",
              [r"north bank", r"مصرف الشمال"]),
    "warka": ("Warka Bank", "بانکی وەرکا", "مصرف الوركاء",
              [r"warka", r"الوركاء"]),
    "erbil": ("Erbil Bank", "بانکی هەولێر", "مصرف أربيل",
              [r"erbil bank", r"مصرف اربيل", r"مصرف أربيل", r"بانکی هەولێر"]),
    "investment": ("Iraqi Investment Bank", "بانکی وەبەرهێنانی عێراقی",
                   "المصرف العراقي للاستثمار",
                   [r"iraqi investment", r"العراقي للاستثمار",
                    r"وەبەرهێنانی عێراقی"]),
    "nibank": ("North Iraq Investment Bank",
               "بانکی وەبەرهێنانی باکووری عێراق",
               "مصرف شمال العراق للاستثمار",
               [r"north iraq investment"]),
    "meib": ("Middle East Investment Bank", "بانکی ڕۆژهەڵاتی ناوەڕاست",
             "مصرف الشرق الأوسط للاستثمار",
             [r"middle east.*invest", r"الشرق الاوسط للاستثمار"]),
    "dijla": ("Dijla & Furat Bank", "بانکی دیجلە و فورات", "مصرف دجلة والفرات",
              [r"dijla", r"tigris.*euphrates", r"دجلة والفرات"]),
    "baraka": ("Baraka Bank", "بانکی بەرەکە", "مصرف البركة",
               [r"\bbaraka\b", r"بەرەکە", r"البركة"]),
    "byblos": ("Byblos Bank", "بانکی بیبلۆس", "بنك بيبلوس",
               [r"byblos", r"بيبلوس"]),
    # NOTE: BBAC's real Arabic name, not a transliteration. Worth a native check.
    "bbac": ("BBAC Bank", "بانکی بی بی ئەی سی", "بنك بيروت والبلاد العربية",
             [r"\bbbac\b"]),
    "myaccount": ("My Account", "هەژمارەکەم", "حسابي",
                  [r"هەژمار", r"my ?account", r"حسابي"]),
}

# Salary-card agents and wallets. They matter to users but are not cash machines.
AGENTS = {
    "qi": ("Qi Card", "کیو کارد", "كي كارد",
           [r"كي كارد", r"كي ?كارت", r"\bqi ?card\b", r"بطاقة ذكية",
            r"smart card"]),
    "fastpay": ("FastPay", "فاستپەی", "فاست بي", [r"fast ?pay", r"فاست ?پەی"]),
    "zaincash": ("Zain Cash", "زەین کاش", "زين كاش", [r"zain ?cash", r"زين كاش"]),
    "nasspay": ("NassPay", "ناس پەی", "ناس باي", [r"nass ?pay"]),
}

# Strings carrying no information: generic words, bare numbers, city names.
NOISE = re.compile(
    r"^\s*(atms?|banks?|بانک|به ?نك|مصرف|صراف|خودپرداز|\d+|[a-z]|yes|no|unnamed)\s*$"
    r"|^\s*(erbil|hawler|duhok|dohuk|sulaymaniya\w*|soran|zakho|ranya|halabja|kirkuk)\s*$",
    re.I,
)


def _match(text, table):
    # The patterns are the last element, so this survives the table gaining
    # further display languages.
    return [key for key, value in table.items()
            if any(re.search(p, text, re.I) for p in value[-1])]


def normalise(raw):
    """Canonical bank ids mentioned in `raw`. Empty when nothing is recognised.

    Returns a list because one kiosk often hosts machines from several banks.
    Matching runs against raw OSM strings, never against the display names
    above, so adding "(NBI)" to a display name cannot affect detection.
    """
    if not raw:
        return []
    text = str(raw).strip()
    if NOISE.match(text):
        return []
    return _match(text, BANKS)


def kind(raw):
    """'agent' when the string names a card agent/wallet rather than a bank."""
    if raw and not NOISE.match(str(raw).strip()) and _match(str(raw), AGENTS):
        return "agent"
    return "atm"


def agents(raw):
    return _match(str(raw), AGENTS) if raw else []


def display(entity_id):
    """(english, sorani, arabic) display names for a canonical id."""
    for table in (BANKS, AGENTS):
        if entity_id in table:
            en, ckb, ar, _ = table[entity_id]
            return en, ckb, ar
    return entity_id, entity_id, entity_id
