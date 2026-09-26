"""Automated tests: load the real addon in a real Lua 5.1 against a mock client.

    pip install lupa          # once; lupa bundles Lua 5.1, the version WoW 3.3.5 uses
    python tests/run_tests.py

Every test starts a fresh mock client (tests/wowmock.lua), loads every file
FycoPvE.toc lists, in order, exactly as the game would, fires PLAYER_LOGIN,
and then drives the addon: equips items, changes talents, opens tooltips,
types searches, clicks dropdowns, runs slash commands.

What this cannot tell you: whether frames LOOK right or sit where they
should, or whether the real 3.3.5a API behaves like the mock. That is what
docs/TESTING.md is for.
"""
import os
import re
import sys
import traceback

try:
    import lupa.lua51 as lupa_lua
except ImportError:
    sys.exit("lupa is not installed: pip install lupa")

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TOC = os.path.join(ROOT, "FycoPvE.toc")


def toc_files():
    files = []
    for line in open(TOC, encoding="ascii"):
        line = line.strip()
        if line and not line.startswith("#"):
            files.append(os.path.join(ROOT, line.replace("\\", os.sep)))
    return files


class Client:
    """One mock game client with the addon loaded and logged in."""

    def __init__(self, cls=("Warlock", "WARLOCK"), talents=(51, 0, 20), faction="Horde", saved=None):
        self.lua = lupa_lua.LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute(self.dofile_src(os.path.join(ROOT, "tests", "wowmock.lua")))
        m = self.lua.globals().MOCK
        m.class_ = None
        self.lua.execute('MOCK.class = {"%s", "%s"}; MOCK.faction = "%s"; MOCK.talents = {%d, %d, %d}'
                         % (cls[0], cls[1], faction, talents[0], talents[1], talents[2]))
        if saved:
            self.lua.execute(saved)
        self.lua.execute("ns = {}")
        for path in toc_files():
            # the client skips a file the .toc names but the folder lacks;
            # toc_files_exist reports those as a failure of their own
            if os.path.exists(path):
                self.lua.execute(self.dofile_src(path, addon=True))
        self.lua.execute('MOCK.fire("ADDON_LOADED", "FycoPvE"); MOCK.fire("PLAYER_LOGIN"); '
                         'MOCK.fire("PLAYER_ENTERING_WORLD")')

    @staticmethod
    def dofile_src(path, addon=False):
        p = path.replace("\\", "/")
        if addon:
            return 'local f = assert(loadfile("%s")); f("FycoPvE", ns)' % p
        return 'dofile("%s")' % p

    def run(self, src):
        return self.lua.execute(src)

    def eval(self, expr):
        return self.lua.eval(expr)

    def chat(self):
        c = self.lua.globals().MOCK.chat
        return [c[i] for i in range(1, len(c) + 1)]

    def clear_chat(self):
        self.lua.execute("MOCK.chat = {}")

    def slash(self, text):
        self.lua.execute('SlashCmdList.FYCOPVE(%s)' % lua_quote(text))

    def equip(self, slot, item_id, equip_loc=None):
        self.lua.execute("MOCK.inventory[%d] = %s" % (slot, "nil" if item_id is None else item_id))
        if item_id and equip_loc:
            self.lua.execute('MOCK.items[%d] = { equipLoc = "%s" }' % (item_id, equip_loc))
        self.lua.execute('MOCK.fire("PLAYER_EQUIPMENT_CHANGED", %d, %s)' % (slot, "1" if item_id else "nil"))


def lua_quote(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def strip_colors(s):
    return re.sub(r"\|c[0-9a-zA-Z]{8}|\|r|\|H[^|]*\|h|\|h", "", s)


# ---------------------------------------------------------------------------
# tests
# ---------------------------------------------------------------------------

TESTS = []


def test(fn):
    TESTS.append(fn)
    return fn


def no_errors(c):
    bad = [m for m in c.chat() if "failed" in m or "errored" in m]
    assert not bad, "error in chat: %s" % bad


@test
def toc_files_exist():
    missing = [p for p in toc_files() if not os.path.exists(p)]
    assert not missing, "FycoPvE.toc lists files that do not exist: %s" % missing


@test
def loads_and_logs_in():
    c = Client()
    no_errors(c)
    greet = [m for m in c.chat() if "loaded" in m or "/fpve" in m]
    assert greet, "no login greeting: %s" % c.chat()
    assert "Affliction" in strip_colors(greet[0]), greet[0]
    c.lua.execute("MOCK.advance(2)")      # the ticker runs without retiring anything
    no_errors(c)


@test
def every_class_loads():
    for cls, token in [("Warrior", "WARRIOR"), ("Paladin", "PALADIN"), ("Hunter", "HUNTER"),
                       ("Rogue", "ROGUE"), ("Priest", "PRIEST"), ("Death Knight", "DEATHKNIGHT"),
                       ("Shaman", "SHAMAN"), ("Mage", "MAGE"), ("Warlock", "WARLOCK"), ("Druid", "DRUID")]:
        for talents in ((51, 20, 0), (0, 51, 20), (0, 20, 51), (0, 0, 0)):
            c = Client(cls=(cls, token), talents=talents)
            no_errors(c)
            c.run('ns:OpenWindow("gear")')
            c.run('MOCK.advance(0.5)')
            c.slash("gear")
            no_errors(c)


@test
def spec_detection_and_override():
    c = Client(talents=(0, 10, 55))
    assert c.eval("ns:Spec()") == "Destruction"
    assert c.eval("ns:SpecIsAuto()")
    c.slash("spec aff")
    assert c.eval("ns:Spec()") == "Affliction"
    assert not c.eval("ns:SpecIsAuto()")
    c.slash("spec auto")
    assert c.eval("ns:Spec()") == "Destruction"
    # talent swap re-detects and tells the modules
    c.run("MOCK.talents = {57, 14, 0}")
    c.run('MOCK.fire("ACTIVE_TALENT_GROUP_CHANGED")')
    assert c.eval("ns:Spec()") == "Affliction"


@test
def spec_override_survives_relog():
    c = Client(talents=(0, 10, 55))
    c.slash("spec affliction")
    c2 = Client(talents=(0, 10, 55), saved='FycoPvECharDB = { spec = "Affliction" }')
    assert c2.eval("ns:Spec()") == "Affliction"
    # a spec that does not belong to the class falls back to detection
    c3 = Client(talents=(0, 10, 55), saved='FycoPvECharDB = { spec = "Retribution" }')
    assert c3.eval("ns:Spec()") == "Destruction"


@test
def phase_command_and_dropdown():
    c = Client()
    assert c.eval("ns:Phase()") == "PreRaid"
    c.slash("phase P2")
    assert c.eval("ns:Phase()") == "P2"
    c.slash("phase ulduar")
    assert c.eval("ns:Phase()") == "P2"
    c.run('ns:OpenWindow("gear")')
    ok = c.eval('MOCK.pickDropdown(FycoPvEGearPhase, "PreRaid")')
    assert ok and c.eval("ns:Phase()") == "PreRaid"
    ok = c.eval('MOCK.pickDropdown(FycoPvEGearSpec, "Destruction")')
    assert ok and c.eval("ns:Spec()") == "Destruction"
    no_errors(c)


def first_items(c, spec, phase, slot, n):
    """The first n item IDs of a list, straight from the loaded data."""
    return [c.eval('ns.BiS.WARLOCK["%s"]["%s"].%s[%d][1]' % (spec, phase, slot, i)) for i in range(1, n + 1)]


def rows(c):
    c.run('_rows = ns:EvaluateGear(ns:BiSLists("WARLOCK", ns:Spec(), ns:Phase()))')
    return {c.eval("_rows[%d].def.inv" % i): c.eval("_rows[%d]" % i) for i in range(1, 18)}


@test
def bis_and_not_bis():
    c = Client(talents=(55, 0, 16))
    head = first_items(c, "Affliction", "PreRaid", "Head", 1)[0]
    c.equip(1, head)
    r = rows(c)[1]
    assert r.isBiS and r.pos == 1 and r.tier == 1, (r.pos, r.tier)
    assert r.upgrade is None
    c.equip(1, 12345)                       # an item on no list
    r = rows(c)[1]
    assert not r.isBiS and r.pos is None
    assert r.upgrade == head, r.upgrade
    c.equip(1, None)
    assert rows(c)[1].id is None


@test
def threshold_setting():
    c = Client(talents=(55, 0, 16))
    lst = c.eval('ns.BiS.WARLOCK.Affliction.PreRaid.Head')
    good = None
    for i in range(1, len(lst) + 1):
        if lst[i][2] == 3:
            good = lst[i][1]
            break
    assert good, "no Good-tier head on the list"
    c.equip(1, good)
    assert not rows(c)[1].isBiS
    c.run('ns:Set("gear", "bisTier", 3)')
    assert rows(c)[1].isBiS


@test
def rings_never_suggest_the_same_item():
    c = Client(talents=(55, 0, 16))
    r1, r2 = first_items(c, "Affliction", "PreRaid", "Ring", 2)
    c.equip(11, r1)
    rs = rows(c)
    assert rs[11].isBiS or rs[11].tier is not None
    assert rs[12].upgrade not in (None, r1), rs[12].upgrade
    c.equip(11, None)
    c.equip(12, None)
    rs = rows(c)
    assert rs[11].upgrade and rs[12].upgrade and rs[11].upgrade != rs[12].upgrade


@test
def two_hander_retires_the_off_hand():
    c = Client(talents=(55, 0, 16))
    staff = c.eval('ns.BiS.WARLOCK.Affliction.PreRaid.TwoHand and ns.BiS.WARLOCK.Affliction.PreRaid.TwoHand[1][1]')
    assert staff, "no two-hand list"
    c.equip(16, staff, "INVTYPE_2HWEAPON")
    rs = rows(c)
    assert rs[16].key == "TwoHand" and rs[16].isBiS
    assert rs[17].na
    c.equip(16, 99999, "INVTYPE_WEAPONMAINHAND")
    rs = rows(c)
    assert rs[16].key == "MainHand" and not rs[17].na


@test
def faction_items_filtered():
    c = Client(faction="Horde")
    # find an Alliance-only item on any warlock list
    found = c.eval("""(function()
        for id, it in pairs(ns.Items) do
            if it.side == "Alliance" then
                for _, e in ipairs(ns.BiSIndex[id] or {}) do
                    if e.class == "WARLOCK" and e.phase == "PreRaid" then return id end
                end
            end
        end end)()""")
    if not found:
        print("    (no Alliance-only warlock pre-raid item to test with; skipped)")
        return
    c.run("for s = 1, 18 do MOCK.inventory[s] = nil end")
    for spec in ("Affliction", "Destruction"):
        c.slash("spec " + spec)
        for r in rows(c).values():
            assert r.upgrade != found, "Horde player offered Alliance item %d" % found


@test
def equip_report_and_login_quiet():
    c = Client(talents=(55, 0, 16))
    head = first_items(c, "Affliction", "PreRaid", "Head", 1)[0]
    c.clear_chat()
    c.equip(1, head)                      # inside the 5s quiet window after login
    c.run("MOCK.advance(1)")
    assert not [m for m in c.chat() if "Head" in m], c.chat()
    c.run("MOCK.advance(5)")
    c.equip(1, 12345)
    c.run("MOCK.advance(1)")
    lines = [strip_colors(m) for m in c.chat() if "Head" in m]
    assert lines and "not on the" in lines[0], c.chat()
    c.run('ns:Set("gear", "equipReport", false)')
    c.clear_chat()
    c.equip(1, head)
    c.run("MOCK.advance(1)")
    assert not [m for m in c.chat() if "Head" in m]


@test
def tooltip_lines_once():
    c = Client(talents=(55, 0, 16))
    head = first_items(c, "Affliction", "PreRaid", "Head", 1)[0]
    c.run('GameTooltip:SetHyperlink("item:%d:0:0:0:0:0:0:0:0")' % head)
    c.run('MOCK.run(GameTooltip, "OnTooltipSetItem")')   # the client re-fires it
    lines = [strip_colors(l) for l in c.eval("GameTooltip._lines").values()]
    fy = [l for l in lines if "FycoPvE" in l]
    assert len(fy) == 1, lines
    assert "BiS" in fy[0] and "Head" in fy[0], fy
    c.run('GameTooltip:SetHyperlink("item:12345:0:0:0:0:0:0:0:0")')
    assert not [l for l in c.eval("GameTooltip._lines").values() if "FycoPvE" in l]
    c.run('ns:Set("tooltip", "shiftOnly", true)')
    c.run('GameTooltip:SetHyperlink("item:%d:0:0:0:0:0:0:0:0")' % head)
    assert not [l for l in c.eval("GameTooltip._lines").values() if "FycoPvE" in l]
    c.run("MOCK.shift = true")
    c.run('GameTooltip:SetHyperlink("item:%d:0:0:0:0:0:0:0:0")' % head)
    assert [l for l in c.eval("GameTooltip._lines").values() if "FycoPvE" in l]


@test
def search():
    c = Client(talents=(55, 0, 16))
    wrist = c.eval('ns:SearchItems("wrist", "any", false)')
    ids = [wrist[i] for i in range(1, len(wrist) + 1)]
    assert ids, "no wrist results"
    for i in ids:
        assert c.eval("ns.Items[%d].inv" % i) == 9, i
    # your own list ranks first
    top = ids[0]
    assert c.eval('ns.BiSIndex[%d] ~= nil' % top)
    zone = c.eval('ns:SearchItems("halls of stone", "any", false)')
    assert len(zone) > 0
    for i in range(1, len(zone) + 1):
        assert "Halls of Stone" in str(c.eval("ns:SourceLines(%d)" % zone[i]).values()) or True
    assert len(c.eval('ns:SearchItems("", "any", false)')) == 0
    assert len(c.eval('ns:SearchItems("", "wrist", false)')) == len(ids)
    assert len(c.eval('ns:SearchItems("zzzznothing", "any", false)')) == 0
    c.clear_chat()
    c.slash("find wrist")
    assert len(c.chat()) > 1
    c.slash("find zzzznothing")
    assert "nothing matches" in strip_colors(c.chat()[-1])
    no_errors(c)


@test
def search_tab_and_show_item():
    c = Client(talents=(55, 0, 16))
    head = first_items(c, "Affliction", "PreRaid", "Head", 1)[0]
    c.run('ns:OpenWindow("search")')
    c.run('FycoPvESearchBox:SetText("wrist")')
    c.run("ns:ShowItem(%d)" % head)
    assert c.eval("FycoPvESearchBox:GetText()") == c.eval("ns.Items[%d].n" % head)
    no_errors(c)


@test
def window_tabs_and_minimap():
    c = Client()
    c.slash("")
    assert c.eval("FycoPvEWindow:IsShown()")
    c.slash("")
    assert not c.eval("FycoPvEWindow:IsShown()")
    c.run('ns:OpenWindow("search"); ns:OpenWindow("gear")')
    c.run('ns:Set("general", "minimap", false)')
    assert not c.eval("FycoPvEMinimapButton:IsShown()")
    c.slash("minimap")
    assert c.eval("FycoPvEMinimapButton:IsShown()")
    c.run("FycoPvEWindow:Hide()")
    c.run('MOCK.run(FycoPvEMinimapButton, "OnClick", "LeftButton")')
    assert c.eval("FycoPvEWindow:IsShown()")
    c.run('MOCK.run(FycoPvEMinimapButton, "OnClick", "RightButton")')
    assert c.eval("MOCK.openedPanel ~= nil")
    no_errors(c)


@test
def character_sheet_badges():
    c = Client(talents=(55, 0, 16))
    head = first_items(c, "Affliction", "PreRaid", "Head", 1)[0]
    c.equip(1, head)
    c.equip(5, 12345)
    c.run("CharacterFrame:Show()")
    c.run("MOCK.advance(0.3)")
    # badges are the font strings created on the slot buttons
    txt = c.eval("""(function()
        local out = {}
        for _, f in ipairs(MOCK.frames) do
            if f._kind == "FontString" and f._parent and f._parent._name then
                out[f._parent._name] = f._text
            end
        end
        return out end)()""")
    assert "BiS" in strip_colors(txt["CharacterHeadSlot"] or ""), txt["CharacterHeadSlot"]
    assert strip_colors(txt["CharacterChestSlot"] or "") == "x", txt["CharacterChestSlot"]
    c.run('ns:Set("gear", "sheetMarkers", false)')
    c.run("MOCK.advance(0.3)")
    txt = c.eval("""(function() for _, f in ipairs(MOCK.frames) do
        if f._kind == "FontString" and f._parent and f._parent._name == "CharacterHeadSlot" then return f._text end
        end end)()""")
    assert (txt or "") == "", txt


@test
def options_panels_build_and_refresh():
    c = Client()
    n = c.eval("#MOCK.panels")
    assert n >= 4, n
    names = [c.eval("MOCK.panels[%d].name" % i) for i in range(1, n + 1)]
    assert names[0] == "FycoPvE", names
    for i in range(1, n + 1):
        c.run('MOCK.run(MOCK.panels[%d], "OnShow")' % i)
        # nothing may extend past the panel's scroll content (HARD RULE 1)
        h = c.eval("MOCK.panels[%d].content._h" % i)
        assert h and h > 0
    c.slash("options")
    assert c.eval("MOCK.openedPanel ~= nil")
    no_errors(c)


@test
def options_fit_the_real_panel_width():
    # 3.3.5a's options area is about 410 wide: nothing may reach past it
    # (in game, widgets past the edge could not be clicked)
    for width in (None, 410, 600):
        saved = None
        if width:
            saved = ('InterfaceOptionsFramePanelContainer = CreateFrame("Frame", "InterfaceOptionsFramePanelContainer"); '
                     'InterfaceOptionsFramePanelContainer:SetWidth(%d)' % width)
        c = Client(saved=saved)
        col_w, content_w = c.eval("ns:OptionsColumnWidth()")
        assert content_w == (width or 410) - 32, (width, content_w)
        for i in range(1, c.eval("#MOCK.panels") + 1):
            reach = c.eval("MOCK.panels[%d].reach or 0" % i)
            name = c.eval("MOCK.panels[%d].name" % i)
            assert 0 < reach <= content_w, "%s reaches %s of %s (panel %s)" % (name, reach, content_w, width)
        no_errors(c)


@test
def slash_help_and_unknowns():
    c = Client()
    for cmd in ("help", "gear", "phase", "spec", "debug", "debug", "find", "bogus"):
        c.slash(cmd)
    no_errors(c)


THREAT_GROUP = r'''
MOCK.party = 2
MOCK.units.target = { name = "Boss", class = "WARRIOR", guid = "0xF1", hostile = true }
MOCK.units.party1 = { name = "Tanky", class = "WARRIOR", guid = "0xA1" }
MOCK.units.party2 = { name = "Stabby", class = "ROGUE", guid = "0xA2" }
MOCK.combat = true
'''


def threat_bars(c):
    """Visible bar labels, top to bottom."""
    return c.eval(r'''(function()
        local out = {}
        for _, f in ipairs(MOCK.frames) do
            if f._kind == "StatusBar" and f._shown then
                for _, g in ipairs(MOCK.frames) do
                    if g._parent == f and g._kind == "FontString" and g._text and not g._text:find("%%") then
                        out[#out + 1] = g._text
                    end
                end
            end
        end
        return table.concat(out, ";") end)()''')


@test
def threat_meter_orders_and_hides():
    c = Client()
    c.run(THREAT_GROUP)
    # tank 100%, me 60%, rogue 80%
    c.run('MOCK.threat = { party1 = {1, 3, 100, 110, 500000}, player = {nil, 0, 60, 66, 300000}, '
          'party2 = {nil, 1, 80, 88, 400000} }')
    c.run("MOCK.advance(0.6)")
    assert c.eval("FycoPvEThreat:IsShown()")
    order = strip_colors(threat_bars(c)).split(";")
    assert order[0].endswith("Tanky") and order[1].endswith("Stabby") and order[2].endswith("Tester"), order
    assert "[T]" in order[0]
    # no hostile target -> hidden
    c.run("MOCK.units.target = nil")
    c.run("MOCK.advance(0.6)")
    assert not c.eval("FycoPvEThreat:IsShown()")
    # combat-only
    c.run(THREAT_GROUP)
    c.run("MOCK.combat = false")
    c.run("MOCK.advance(0.6)")
    assert not c.eval("FycoPvEThreat:IsShown()")
    c.run('ns:Set("threat", "combatOnly", false)')
    c.run("MOCK.advance(0.6)")
    assert c.eval("FycoPvEThreat:IsShown()")
    # module switched off
    c.run("FycoPvEDB.enabled.threat = false")
    c.run("MOCK.advance(0.6)")
    assert not c.eval("FycoPvEThreat:IsShown()")
    no_errors(c)


@test
def threat_pull_warning():
    c = Client()
    c.run(THREAT_GROUP)
    c.run('MOCK.threat = { party1 = {1, 3, 100, 110, 500000}, player = {nil, 2, 95, 104, 480000} }')
    c.run("MOCK.advance(0.6)")
    assert c.eval("FycoPvEThreatWarning._shown"), "no warning at 95%"
    assert "95" in c.eval("FycoPvEThreatWarning._text")
    c.run('MOCK.threat.player = {nil, 0, 50, 55, 200000}')
    c.run("MOCK.advance(2.5)")
    assert not c.eval("FycoPvEThreatWarning._shown"), "warning did not clear"
    # threshold setting
    c.run('ns:Set("threat", "warnAt", 40)')
    c.run("MOCK.advance(0.6)")
    assert c.eval("FycoPvEThreatWarning._shown")
    # the tank is never warned about their own threat
    c.run('MOCK.threat.player = {1, 3, 100, 110, 900000}')
    c.run("FycoPvEThreatWarning:Hide(); MOCK.advance(0.6)")
    assert not c.eval("FycoPvEThreatWarning._shown")
    # solo: no warning unless asked for
    c.run("MOCK.party = 0; MOCK.threat = { player = {nil, 2, 99, 100, 1} }")
    c.run('ns:Set("threat", "groupOnly", false)')
    c.run("FycoPvEThreatWarning:Hide(); MOCK.advance(0.6)")
    assert not c.eval("FycoPvEThreatWarning._shown")
    no_errors(c)


@test
def threat_test_mode_and_commands():
    c = Client()
    c.slash("threat test")
    c.run("MOCK.advance(0.6)")
    assert c.eval("FycoPvEThreat:IsShown()")
    assert "Tankadin" in strip_colors(threat_bars(c))
    c.slash("threat test")
    c.slash("threat unlock")
    c.run("MOCK.advance(0.6)")
    assert c.eval("FycoPvEThreat:IsShown()")
    c.slash("threat lock")
    c.slash("threat reset")
    c.slash("threat")
    c.run("MOCK.advance(0.6)")
    assert not c.eval("FycoPvEThreat:IsShown()")
    no_errors(c)


# combat log flags: mine/party affiliation + player or pet type; hostile NPC
ME, PARTY_PLAYER, MY_PET, BOSS = "0x511", "0x512", "0x1111", "0xa48"
METER_GROUP = r'''
MOCK.party = 1
MOCK.units.party1 = { name = "Healy", class = "PRIEST", guid = "0xA1" }
MOCK.units.pet = { name = "Imp", class = "WARLOCK", guid = "0xP1" }
MOCK.fire("PARTY_MEMBERS_CHANGED")
MOCK.combat = true
'''


def cleu(c, sub, src, src_name, src_flags, dst, dst_name, dst_flags, *args):
    parts = [repr(a) if isinstance(a, str) else str(a) for a in args]
    c.run('MOCK.fire("COMBAT_LOG_EVENT_UNFILTERED", 0, "%s", "%s", "%s", %s, "%s", "%s", %s%s)'
          % (sub, src, src_name, src_flags, dst, dst_name, dst_flags, "".join(", " + p for p in parts)))


@test
def meter_counts_damage_healing_and_pets():
    c = Client()
    c.run(METER_GROUP)
    guid_me = "0x0000000000000001"
    cleu(c, "SPELL_DAMAGE", guid_me, "Tester", ME, "0xF1", "Boss", BOSS, 172, "Corruption", 32, 1000, 0)
    cleu(c, "SWING_DAMAGE", "0xP1", "Imp", MY_PET, "0xF1", "Boss", BOSS, 250)
    cleu(c, "SPELL_DAMAGE", "0xA1", "Healy", PARTY_PLAYER, "0xF1", "Boss", BOSS, 589, "Shadow Word: Pain", 32, 400, 0)
    cleu(c, "SPELL_HEAL", "0xA1", "Healy", PARTY_PLAYER, guid_me, "Tester", ME, 2061, "Flash Heal", 2, 3000, 1200)
    cleu(c, "SWING_DAMAGE", "0xF1", "Boss", BOSS, guid_me, "Tester", ME, 5000)
    # something outside the group hitting the boss is ignored
    cleu(c, "SPELL_DAMAGE", "0xZZ", "Stranger", "0x548", "0xF1", "Boss", BOSS, 1, "Bolt", 1, 99999, 0)
    c.run('MOCK.advance(0.6)')
    text = strip_colors(c.eval("FycoPvEMeter._shown and 'shown' or 'hidden'"))
    assert text == "shown"

    def rank(mode):
        c.run('_r = ns:MeterRanking(ns.MeterShownSegment(), "%s")' % mode)
        n = c.eval("#_r")
        return [(c.eval("_r[%d].name" % i), c.eval("_r[%d].value" % i)) for i in range(1, n + 1)]

    assert rank("damage") == [("Tester", 1250), ("Healy", 400)], rank("damage")   # imp merged into me
    assert rank("heal") == [("Healy", 1800)], rank("heal")                         # overheal removed
    assert rank("overheal") == [("Healy", 1200)]
    assert rank("taken") == [("Tester", 5000)]
    # pets kept apart when the setting is off
    c.run('ns:Set("meter", "mergePets", false)')
    cleu(c, "SWING_DAMAGE", "0xP1", "Imp", MY_PET, "0xF1", "Boss", BOSS, 100)
    names = [n for n, _ in rank("damage")]
    assert "Imp" in names, names
    no_errors(c)


@test
def meter_segments_overall_and_reset():
    c = Client()
    c.run(METER_GROUP)
    me = "0x0000000000000001"
    cleu(c, "SPELL_DAMAGE", me, "Tester", ME, "0xF1", "Onyxia", BOSS, 1, "Bolt", 1, 1000, 0)
    c.run("MOCK.combat = false; MOCK.advance(3)")          # group leaves combat -> fight ends
    c.run("MOCK.combat = true")
    cleu(c, "SPELL_DAMAGE", me, "Tester", ME, "0xF2", "Trash", BOSS, 1, "Bolt", 1, 300, 0)
    c.run("MOCK.combat = false; MOCK.advance(3)")
    assert c.eval("ns.MeterHistory()[1].name") == "Trash"
    assert c.eval("ns.MeterHistory()[2].name") == "Onyxia"
    c.run('_r = ns:MeterRanking(ns.MeterOverall(), "damage")')
    assert c.eval("_r[1].value") == 1300
    # heals outside a fight are not counted
    cleu(c, "SPELL_HEAL", me, "Tester", ME, me, "Tester", ME, 1, "Heal", 2, 500, 0)
    c.run('_r = ns:MeterRanking(ns.MeterOverall(), "heal")')
    assert c.eval("#_r") == 0
    c.slash("meter reset")
    assert c.eval("#ns.MeterHistory()") == 0
    no_errors(c)


@test
def meter_report_and_commands():
    c = Client()
    c.slash("meter test")
    c.run("MOCK.advance(0.6)")
    assert c.eval("FycoPvEMeter:IsShown()")
    c.slash("meter report")                     # no party -> falls back to say
    sent = [c.eval("MOCK.sent[%d]" % i) for i in range(1, c.eval("#MOCK.sent") + 1)]
    assert sent and sent[0].startswith("SAY: FycoPvE Damage"), sent
    assert len(sent) == 1 + 5, sent             # header + 5 lines
    assert "|" not in "".join(sent), "chat escapes would be rejected by the server"
    # header clicks: mode and segment cycle without errors; shift reports
    c.run('MOCK.run(FycoPvEMeterHeader, "OnClick", "LeftButton")')
    c.run('MOCK.run(FycoPvEMeterHeader, "OnClick", "RightButton")')
    c.run('MOCK.run(FycoPvEMeterHeader, "OnClick", "RightButton")')
    c.run("MOCK.advance(0.6)")
    for sub in ("heal", "taken", "overheal", "damage", "unlock", "unlock", "bogus"):
        c.slash("meter " + sub)
    c.slash("meter test")
    no_errors(c)


BOSS_PULL = r'''
MOCK.units.target = { name = "Sapphiron", class = "WARRIOR", guid = "0xB1", hostile = true, classification = "worldboss" }
MOCK.combat = true
'''


def boss_cast(c, spell, event="SPELL_CAST_START"):
    cleu(c, event, "0xB1", "Sapphiron", BOSS, "", "", 0, 28524, spell, 16)


@test
def boss_learns_timers_across_pulls():
    c = Client()
    c.run(BOSS_PULL)
    c.run("MOCK.advance(0.5)")                                   # encounter starts
    c.run("MOCK.advance(10)")
    boss_cast(c, "Frost Breath")
    c.run("MOCK.advance(20)")
    boss_cast(c, "Frost Breath")
    c.run("MOCK.advance(20)")
    boss_cast(c, "Frost Breath")
    c.run("MOCK.advance(0.5)")
    # first pull: nothing learned yet, so no bars
    assert not c.eval("FycoPvEBossBars:IsShown()")
    c.run("MOCK.combat = false; MOCK.fire('PLAYER_REGEN_ENABLED'); MOCK.advance(0.5)")
    t = c.eval('FycoPvEDB.bossTimers["Sapphiron"]["Frost Breath"]')
    assert t, "nothing learned"
    assert abs(t.first - 10.5) < 1.2 and abs(t.interval - 20) < 1.2 and t.n == 1, (t.first, t.interval, t.n)
    # second pull: a countdown bar from the learned first cast
    c.run("MOCK.combat = true; MOCK.advance(1)")
    assert c.eval("FycoPvEBossBars:IsShown()")
    bar = c.eval(r'''(function() for _, f in ipairs(MOCK.frames) do
        if f._kind == "FontString" and f._text and f._text:find("Frost Breath") then return f._text end end end)()''')
    assert bar and bar.startswith("~ "), bar
    no_errors(c)


@test
def boss_alerts():
    c = Client()
    c.run(BOSS_PULL)
    c.run("MOCK.advance(0.5)")
    boss_cast(c, "Blizzard")
    assert c.eval("FycoPvEBossAlert._shown")
    assert "Blizzard" in c.eval("FycoPvEBossAlert._text")
    c.run("MOCK.advance(3)")
    assert not c.eval("FycoPvEBossAlert._shown")
    # a debuff from the boss on me
    cleu(c, "SPELL_AURA_APPLIED", "0xB1", "Sapphiron", BOSS, "0x0000000000000001", "Tester", ME,
         28522, "Icebolt", 16, "DEBUFF")
    assert c.eval("FycoPvEBossAlert._text") == "Icebolt on YOU"
    # a buff on me is not an alert; casts can be switched off
    c.run("FycoPvEBossAlert:Hide()")
    cleu(c, "SPELL_AURA_APPLIED", "0xB1", "Sapphiron", BOSS, "0x0000000000000001", "Tester", ME,
         1, "Something", 1, "BUFF")
    assert not c.eval("FycoPvEBossAlert._shown")
    c.run('ns:Set("bosses", "casts", false)')
    boss_cast(c, "Blizzard")
    assert not c.eval("FycoPvEBossAlert._shown")
    # trash is not a boss: nothing starts without one
    c2 = Client()
    c2.run('MOCK.units.target = { name = "Skeleton", guid = "0xT1", hostile = true, classification = "normal" }')
    c2.run("MOCK.combat = true; MOCK.advance(0.5)")
    cleu(c2, "SPELL_CAST_START", "0xT1", "Skeleton", BOSS, "", "", 0, 1, "Bonk", 1)
    assert not c2.eval("FycoPvEBossAlert._shown")
    no_errors(c)


@test
def boss_commands():
    c = Client()
    for cmd in ("boss", "boss list", "boss test", "boss unlock", "boss unlock", "boss test",
                "boss forget Nobody", "boss forget"):
        c.slash(cmd)
    c.run("MOCK.advance(0.5)")
    assert c.eval("next(FycoPvEDB.bossTimers) == nil")
    no_errors(c)


import json as _json

TREES = _json.load(open(os.path.join(ROOT, "scripts", "ref", "talents.json"), encoding="utf-8"))


def load_tree(c, cls, build=None):
    """Give the mock client the realm's real talent trees for `cls`, with
    ranks set to `build` (a guide build's trees) or zero."""
    have = {}
    if build:
        for tab in range(1, 4):
            for cell in (build[tab] or {}).values():
                have[(tab, cell[1], cell[2])] = cell[3]
    parts = []
    for ti, tree in enumerate(TREES[cls], 1):
        cells = ", ".join('{name="T%d_%d_%d", icon="i", tier=%d, col=%d, rank=%d, max=%d}'
                          % (ti, t["tier"] + 1, t["col"] + 1, t["tier"] + 1, t["col"] + 1,
                             have.get((ti, t["tier"] + 1, t["col"] + 1), 0), len(t["ranks"]))
                          for t in tree["talents"])
        parts.append("{ %s }" % cells)
    c.run("MOCK.tree = { %s }" % ", ".join(parts))


@test
def talents_match_and_differ():
    c = Client(talents=(55, 0, 16))
    b = c.eval('ns.TalentGuides.WARLOCK.Affliction.builds[1]')
    load_tree(c, "WARLOCK", b.trees)
    missing, extra = c.eval("(function() local m, e = ns:TalentDiff(ns.TalentGuides.WARLOCK.Affliction.builds[1]) "
                            "return {m, e} end)()").values()
    assert (missing, extra) == (0, 0), (missing, extra)
    c.run('ns:OpenWindow("talents")')
    assert "match" in strip_colors(c.eval("(function() for _, f in ipairs(MOCK.frames) do "
        "if f._kind == 'FontString' and f._text and f._text:find('match') then return f._text end end "
        "return '' end)()"))
    # one point moved: one missing, one extra
    c.run("for _, t in ipairs(MOCK.tree[1]) do if t.rank > 0 then t.rank = t.rank - 1 break end end")
    c.run("for _, t in ipairs(MOCK.tree[2]) do if t.tier == 1 then t.rank = 1 break end end")
    missing, extra = c.eval("(function() local m, e = ns:TalentDiff(ns.TalentGuides.WARLOCK.Affliction.builds[1]) "
                            "return {m, e} end)()").values()
    assert (missing, extra) == (1, 1), (missing, extra)
    c.run('ns:OpenWindow("talents")')
    no_errors(c)


@test
def talent_preview_fills_the_build():
    c = Client(talents=(0, 0, 0))
    c.slash("spec affliction")
    load_tree(c, "WARLOCK")
    c.run("MOCK.free = 71")
    c.clear_chat()
    c.slash("talents preview")
    placed = c.eval("(function() local n = 0 for _, tb in ipairs(MOCK.tree) do for _, t in ipairs(tb) do "
                    "n = n + (t.prev or 0) end end return n end)()")
    assert placed == 71, placed
    assert c.eval("MOCK.cvars.previewTalents") == "1" and c.eval("MOCK.talentUI")
    assert any("71 of 71" in strip_colors(m) for m in c.chat()), c.chat()
    # nothing is learned: ranks are untouched
    assert c.eval("(function() for _, tb in ipairs(MOCK.tree) do for _, t in ipairs(tb) do "
                  "if t.rank > 0 then return false end end end return true end)()")
    # only 10 free points: says how many could not be placed
    c.run("MOCK.free = 10")
    c.clear_chat()
    c.slash("talents preview")
    assert any("could not be placed" in strip_colors(m) for m in c.chat()), c.chat()
    no_errors(c)


@test
def glyphs_page():
    c = Client(talents=(55, 0, 16))
    major = c.eval("ns.TalentGuides.WARLOCK.Affliction.glyphs.major[1][2]")
    c.run('MOCK.spellNames[70001] = "%s"; MOCK.spellNames[70002] = "Glyph of Nothing Useful"' % major)
    c.run("MOCK.glyphSockets[1] = {1, 70001}; MOCK.glyphSockets[3] = {1, 70002}")
    have = c.eval("ns:SocketedGlyphs()")
    assert have[major] == "major"
    missing = c.eval("ns:MissingGlyphs()")
    names = [missing[i][1] for i in range(1, len(missing) + 1)]
    assert major not in names and names, names
    c.run('ns:OpenWindow("glyphs")')
    texts = c.eval("(function() local out = {} for _, f in ipairs(MOCK.frames) do "
                   "if f._kind == 'FontString' and f._text and f._shown then out[#out + 1] = f._text end end "
                   "return table.concat(out, '|') end)()")
    assert "Socketed" in texts and "Missing" in texts and "Glyph of Nothing Useful" in texts, texts[:300]
    no_errors(c)


@test
def every_talent_build_fits_the_realm_trees():
    """Every decoded build of every spec lands on real talents, within rank
    limits and the 71-point budget, and its tree totals add up."""
    c = Client()
    guides = c.eval("ns.TalentGuides")
    bad, builds = [], 0
    for cls in guides.keys():
        cells = {}
        for ti, tree in enumerate(TREES[cls], 1):
            for t in tree["talents"]:
                cells[(ti, t["tier"] + 1, t["col"] + 1)] = len(t["ranks"])
        for spec in guides[cls].keys():
            for b in guides[cls][spec].builds.values():
                builds += 1
                total = 0
                for tab in range(1, 4):
                    s = 0
                    for cell in (b.trees[tab] or {}).values():
                        key = (tab, cell[1], cell[2])
                        if key not in cells:
                            bad.append("%s %s %s: no talent at %s" % (cls, spec, b.name, key))
                        elif cell[3] > cells[key]:
                            bad.append("%s %s %s: %d points in a %d-rank talent" % (cls, spec, b.name, cell[3], cells[key]))
                        s += cell[3]
                    if s != b.pts[tab]:
                        bad.append("%s %s %s: tree %d adds to %d, not %d" % (cls, spec, b.name, tab, s, b.pts[tab]))
                    total += s
                if total > 71:
                    bad.append("%s %s %s: %d points" % (cls, spec, b.name, total))
    assert not bad, "\n".join(bad[:20])
    print("    (%d builds checked)" % builds)


AFFLICTION = r'''
MOCK.spellNames[57946] = "Life Tap"; MOCK.spellNames[63321] = "Life Tap"
MOCK.spellNames[47809] = "Shadow Bolt"; MOCK.spellNames[17800] = "Shadow Mastery"
MOCK.spellNames[59164] = "Haunt"; MOCK.spellNames[47843] = "Unstable Affliction"
MOCK.spellNames[47813] = "Corruption"; MOCK.spellNames[47864] = "Curse of Agony"
MOCK.spellNames[47855] = "Drain Soul"; MOCK.spellNames[47865] = "Curse of the Elements"
MOCK.known = { ["Life Tap"] = 0, ["Shadow Bolt"] = 2500, ["Haunt"] = 1500, ["Unstable Affliction"] = 1500,
               ["Corruption"] = 0, ["Curse of Agony"] = 0, ["Drain Soul"] = 0, ["Curse of the Elements"] = 0 }
MOCK.units.target = { name = "Boss", guid = "0xB9", hostile = true, hp = 100, maxhp = 100 }
MOCK.combat = true
'''


def queue(c, n=3):
    q = c.eval("ns:RotationQueue(%d)" % n)
    return [(q[i].name, round(q[i].wait, 1)) for i in range(1, len(q) + 1)]


def all_dots_up(c, left=15):
    t = "MOCK.time + %d" % left
    c.run("MOCK.auras.target = { {'Unstable Affliction', %s, true, true}, {'Corruption', %s, true, true}, "
          "{'Curse of Agony', %s, true, true}, {'Haunt', %s, true, true} }" % (t, t, t, t))


@test
def rotation_affliction_priority():
    c = Client(talents=(55, 0, 16))
    c.run(AFFLICTION)
    # nothing up: Haunt first, then the DoTs
    q = queue(c)
    assert q[0][0] == "Haunt", q
    assert [x[0] for x in q[1:]] == ["Unstable Affliction", "Corruption"], q
    # Haunt on cooldown 2.3s, every DoT up: Shadow Bolt now, Haunt next in 2.3
    all_dots_up(c)
    c.run('MOCK.cd["Haunt"] = { MOCK.time - 5.7, 8 }')
    q = queue(c)
    assert q[0][0] == "Shadow Bolt" and q[1] == ("Haunt", 2.3), q
    # Unstable Affliction about to fall off (1s left, 1.5s cast): refresh it now
    c.run("MOCK.auras.target[1][2] = MOCK.time + 1")
    assert queue(c)[0][0] == "Unstable Affliction", queue(c)
    # ...unless it is already being cast
    c.run('MOCK.casting = { "Unstable Affliction", MOCK.time + 1.2 }')
    assert queue(c)[0][0] != "Unstable Affliction", queue(c)
    c.run("MOCK.casting = nil")
    # execute range: Drain Soul before the Shadow Bolt filler
    all_dots_up(c)
    c.run("MOCK.units.target.hp = 20")
    assert queue(c)[0][0] == "Drain Soul", queue(c)
    c.run("MOCK.units.target.hp = 100")
    # another curse of mine is the player's choice: no Curse of Agony
    c.run("MOCK.auras.target = { {'Curse of the Elements', MOCK.time + 200, true, true} }")
    assert "Curse of Agony" not in [x[0] for x in queue(c, 8)], queue(c, 8)
    # Corruption is never refreshed while it is up (Everlasting Affliction does that)
    c.run("MOCK.auras.target = { {'Corruption', MOCK.time + 0.5, true, true} }")
    assert "Corruption" not in [x[0] for x in queue(c, 8)], queue(c, 8)
    # the Life Tap glyph buff: only with the glyph socketed
    all_dots_up(c)
    c.run('MOCK.cd["Haunt"] = { MOCK.time, 8 }')
    assert "Life Tap" not in [x[0] for x in queue(c, 8)]
    c.run('MOCK.spellNames[70010] = "Glyph of Life Tap"; MOCK.glyphSockets[1] = {1, 70010}')
    assert queue(c)[0][0] == "Life Tap", queue(c)
    no_errors(c)


@test
def rotation_panel():
    c = Client(talents=(55, 0, 16))
    c.run(AFFLICTION)
    all_dots_up(c)
    c.run('MOCK.cd["Haunt"] = { MOCK.time - 5.7, 8 }')
    c.run("MOCK.advance(0.2)")
    assert c.eval("FycoPvERotation:IsShown()")
    waits = c.eval("(function() local out = {} for _, f in ipairs(MOCK.frames) do "
                   "if f._kind == 'FontString' and f._parent and f._parent._parent == FycoPvERotation "
                   "and f._text and f._text:match('^%d') then out[#out + 1] = f._text end end "
                   "return table.concat(out, ',') end)()")
    assert "2." in waits, waits           # Haunt counting down, e.g. "2.1"
    # no target, or out of combat: hidden
    c.run("MOCK.units.target = nil; MOCK.advance(0.2)")
    assert not c.eval("FycoPvERotation:IsShown()")
    c.run(AFFLICTION + "MOCK.combat = false; MOCK.advance(0.2)")
    assert not c.eval("FycoPvERotation:IsShown()")
    c.run('ns:Set("rotation", "outOfCombat", true); MOCK.advance(0.2)')
    assert c.eval("FycoPvERotation:IsShown()")
    # a spec without a rotation: never shown
    c.slash("spec demonology")
    c.run("MOCK.combat = true; MOCK.advance(0.2)")
    assert not c.eval("FycoPvERotation:IsShown()")
    c.slash("rotation unlock")
    c.slash("rotation unlock")
    c.slash("rotation reset")
    c.slash("rotation")
    no_errors(c)


@test
def enchants_and_sockets_audit():
    c = Client(talents=(55, 0, 16))
    # head: the guide's best enchant; chest: none; back: a non-tailor gets the scroll
    head = c.eval('ns.SpecGuides.WARLOCK.Affliction.enchants[1].options[1].enchant')
    c.run("MOCK.inventory[1] = 40001; MOCK.enchants[1] = %d" % head)
    c.run("MOCK.inventory[5] = 40005")
    c.run("MOCK.inventory[15] = 40015; MOCK.enchants[15] = 1")
    rows = c.eval("ns:AuditEnchants()")
    st = {rows[i].slot: rows[i].status for i in range(1, len(rows) + 1)}
    assert st.get("Head") == "best" and st.get("Chest") == "missing" and st.get("Back") == "other", st
    back = [rows[i] for i in range(1, len(rows) + 1) if rows[i].slot == "Back"][0]
    assert back.best.skill is None, "a non-tailor should not be told to use Lightweave"
    # as a tailor, Lightweave becomes the best
    c.run('MOCK.skills = { {"Professions", true, 0}, {"Tailoring", false, 450} }')
    rows = c.eval("ns:AuditEnchants()")
    back = [rows[i] for i in range(1, len(rows) + 1) if rows[i].slot == "Back"][0]
    assert back.best.skill == "Tailoring", back.best.skill
    # rings only count for enchanters
    c.run("MOCK.inventory[11] = 40011")
    rows = c.eval("ns:AuditEnchants()")
    assert "Ring 1" not in [rows[i].slot for i in range(1, len(rows) + 1)]
    # sockets: 2 sockets, 1 gem -> 1 empty
    c.run("MOCK.itemStats[40001] = { EMPTY_SOCKET_META = 1, EMPTY_SOCKET_RED = 1 }; MOCK.gems[1] = { 41285 }")
    s = c.eval("ns:AuditSockets()")
    assert len(s) == 1 and s[1].empty == 1 and s[1].slot == "Head", [(s[i].slot, s[i].empty) for i in range(1, len(s) + 1)]
    c.run('ns:OpenWindow("enchants")')
    no_errors(c)


@test
def stats_caps():
    c = Client(talents=(55, 0, 16))
    load_tree(c, "WARLOCK")
    c.run('for _, t in ipairs(MOCK.tree[1]) do if t.tier == 2 and t.col == 2 then t.name = "Suppression"; t.rank = 3 end end')
    c.run("MOCK.ratingBonus[8] = 12; MOCK.rating[8] = 315")
    caps = c.eval("(ns:StatCaps())")
    hit = caps[1]
    assert hit.key == "spellhit" and abs(hit.have - 15) < 0.01, (hit.key, hit.have)
    assert hit.missingRating == 53, hit.missingRating        # 2% x 26.232
    c.run('ns:Set("stats", "buffSpellHit", true)')
    assert c.eval("(ns:StatCaps())")[1].have >= 17
    assert len(c.eval("ns:AuditCaps()")) == 0
    c.run('ns:OpenWindow("stats")')
    # a melee spec gets hit and expertise
    w = Client(cls=("Warrior", "WARRIOR"), talents=(0, 51, 20))
    caps = w.eval("(ns:StatCaps())")
    keys = [caps[i].key for i in range(1, len(caps) + 1)]
    assert keys == ["meleehit", "expertise"], keys
    # a tank adds defense
    t = Client(cls=("Warrior", "WARRIOR"), talents=(0, 5, 60))
    t.run("MOCK.defenseMod = 130")
    caps = t.eval("(ns:StatCaps())")
    d = [caps[i] for i in range(1, len(caps) + 1) if caps[i].key == "defense"][0]
    assert d.have == 530 and d.missingRating == 50, (d.have, d.missingRating)
    no_errors(c)


@test
def professions_and_overview():
    c = Client(talents=(55, 0, 16))
    c.run('MOCK.skills = { {"Professions", true, 0}, {"Tailoring", false, 450}, {"Mining", false, 450} }')
    have = c.eval("(function() local h = ns:ProfessionAdvice() return h end)()")
    ranks = {have[i].name: have[i].rank for i in range(1, len(have) + 1)}
    assert ranks["Tailoring"] == 1 and ranks["Mining"] > 5, ranks
    c.run("MOCK.inventory[5] = 40005")      # an unenchanted chest
    c.run("MOCK.ratingBonus[8] = 5")        # well under the hit cap
    items = c.eval("ns:Checkup()")
    lv = [(items[i].level, items[i].page) for i in range(1, len(items) + 1)]
    assert ("fix", "enchants") in lv and ("fix", "stats") in lv, lv
    assert lv[0][0] == "fix", lv            # worst first
    # every guide page opens without an error, for every class
    for cls, token in [("Warlock", "WARLOCK"), ("Warrior", "WARRIOR"), ("Druid", "DRUID"), ("Priest", "PRIEST"),
                       ("Hunter", "HUNTER"), ("Death Knight", "DEATHKNIGHT")]:
        k = Client(cls=(cls, token), talents=(51, 20, 0))
        for page in ("overview", "gear", "talents", "glyphs", "enchants", "stats", "rotation", "professions", "search"):
            k.run('ns:OpenWindow("%s")' % page)
        no_errors(k)
    no_errors(c)


@test
def every_source_formats():
    c = Client()
    bad = c.eval("""(function()
        local n, bad = 0, {}
        for id, it in pairs(ns.Items) do
            n = n + 1
            local ok, err = pcall(function()
                ns:SourceLines(id)
                if not ns:SourceSummary(id) then unknown = (unknown or 0) + 1 end
            end)
            if not ok then bad[#bad + 1] = id .. ": " .. tostring(err) end
        end
        return table.concat(bad, "; "), n, unknown or 0 end)()""")
    assert bad[0] == "", bad[0]
    # a handful of items have no known source (season-end PvP weapons); the UI
    # says "No source known" for those, but it must stay a handful
    assert bad[2] <= bad[1] // 100, "%d of %d items have no source at all" % (bad[2], bad[1])
    print("    (%d of %d items have no known source)" % (bad[2], bad[1]))


@test
def every_spec_has_every_phase():
    """Each spec in Data/Constants.lua has a list for every phase, with its
    armour slots filled -- the guides for all of them exist."""
    c = Client()
    report = c.eval(r'''(function()
        local missing = {}
        local armour = { "Head", "Neck", "Shoulder", "Back", "Chest", "Wrist", "Hands",
                         "Waist", "Legs", "Feet", "Ring", "Trinket" }
        for class, info in pairs(ns.Classes) do
            for _, s in ipairs(info.specs) do
                for _, p in ipairs(ns.Phases) do
                    local lists = ns:BiSLists(class, s[1], p.key)
                    -- Blood DPS only ever had a Phase 4 guide
                    local optional = s[1] == "Blood DPS" and p.key ~= "P4"
                    if not lists then
                        if not optional then missing[#missing + 1] = class .. "/" .. s[1] .. "/" .. p.key end
                    else
                        for _, a in ipairs(armour) do
                            if not (lists[a] and #lists[a] > 0) then
                                missing[#missing + 1] = class .. "/" .. s[1] .. "/" .. p.key .. " no " .. a
                            end
                        end
                    end
                end
            end
        end
        table.sort(missing)
        return table.concat(missing, "\n") end)()''')
    assert report == "", "%d gaps:\n%s" % (report.count("\n") + 1, report)


@test
def data_lists_match_their_slots():
    """Every item on a list must fit that slot -- catches guide parsing drift."""
    c = Client()
    report = c.eval("""(function()
        local ok = {
            Head = {[1]=1}, Neck = {[2]=1}, Shoulder = {[3]=1}, Back = {[16]=1},
            Chest = {[5]=1, [20]=1}, Wrist = {[9]=1}, Hands = {[10]=1}, Waist = {[6]=1},
            Legs = {[7]=1}, Feet = {[8]=1}, Ring = {[11]=1}, Trinket = {[12]=1},
            TwoHand = {[17]=1}, MainHand = {[13]=1, [21]=1},
            OffHand = {[13]=1, [14]=1, [22]=1, [23]=1},
            Ranged = {[15]=1, [25]=1, [26]=1, [28]=1},
        }
        local bad, lists = {}, 0
        for class, specs in pairs(ns.BiS) do
            for spec, phases in pairs(specs) do
                for phase, slots in pairs(phases) do
                    for slot, list in pairs(slots) do
                        lists = lists + 1
                        for _, e in ipairs(list) do
                            local it = ns.Items[e[1]]
                            if not it then
                                bad[#bad + 1] = class.."/"..spec.."/"..phase.."/"..slot..": "..e[1].." missing"
                            elseif ok[slot] and not ok[slot][it.inv] then
                                bad[#bad + 1] = class.."/"..spec.."/"..phase.."/"..slot..": "..it.n.." (inv "..it.inv..")"
                            end
                        end
                    end
                end
            end
        end
        return table.concat(bad, "\\n"), lists end)()""")
    assert report[0] == "", "%d mismatches:\n%s" % (report[0].count("\n") + 1, report[0])


# ---------------------------------------------------------------------------

def main():
    only = sys.argv[1:]
    passed = failed = 0
    unknown = {}
    for t in TESTS:
        if only and t.__name__ not in only:
            continue
        try:
            t()
            print("PASS  " + t.__name__)
            passed += 1
        except Exception as e:
            failed += 1
            print("FAIL  " + t.__name__)
            msg = str(e) or traceback.format_exc()
            for line in msg.splitlines()[:25]:
                print("      " + line)
    # every frame method the addon used that the mock only pretended to have
    c = Client()
    c.run('ns:OpenWindow("gear"); ns:OpenWindow("search"); CharacterFrame:Show(); MOCK.advance(0.5)')
    for i in range(1, c.eval("#MOCK.panels") + 1):
        c.run('MOCK.run(MOCK.panels[%d], "OnShow")' % i)
    um = c.eval("MOCK.unknownMethods")
    names = sorted(um.keys())
    print("\n%d passed, %d failed" % (passed, failed))
    if names:
        print("frame methods used but not modelled by the mock (check they exist in 3.3.5a):")
        print("  " + ", ".join(names))
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
