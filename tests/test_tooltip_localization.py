import os, sys, unittest, re
from pathlib import Path
if os.environ.get("HPC_TEST_DEPS"):
    sys.path.insert(0, os.environ["HPC_TEST_DEPS"])
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

class TooltipLocalizationTests(unittest.TestCase):
    def setUp(self):
        self.lua=LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            function GetLocale() return 'zhTW' end
            ns={W={ACCENT={1,1,1}},db={},GetScore=function() return 5,1,468,4845 end,
                SortedBoard=function() return {{name='me'}} end, IsMe=function() return true end}
            lines={}; GameTooltip={SetOwner=function() end,Show=function() end,
                AddLine=function(_, text) table.insert(lines,text) end,
                AddDoubleLine=function(_, text, value) table.insert(lines,text); table.insert(lines,value) end}
        """)
        self.ns=self.lua.globals().ns
        for name in ('Locale/enUS.lua','Locale/zhTW.lua'):
            self.lua.execute('return function(...) '+(ROOT/name).read_text(encoding='utf-8-sig')+'\nend')('addon',self.ns)

    def test_static_button_tooltips_have_traditional_translations(self):
        for path in (ROOT/'UI/Main.lua', ROOT/'UI/Board.lua'):
            code=path.read_text(encoding='utf-8-sig')
            for literal in re.findall(r'\.tooltip\s*=\s*("(?:\\.|[^"\\])*")', code):
                value=self.lua.eval(literal)
                self.assertNotEqual(self.ns.L[value], value, (path.name, value))

    def test_minimap_tooltip_displays_translated_labels_and_actions(self):
        code=(ROOT/'UI/Extras.lua').read_text(encoding='utf-8-sig')
        snippet=code[code.index('local function ScoreTooltip'):code.index('ns.ScoreTooltip = ScoreTooltip')]
        self.lua.execute('local ns=...; local L=ns.L\n'+snippet+'\nScoreTooltip({})',self.ns)
        text=' '.join(str(v) for v in self.lua.globals().lines.values())
        for expected in ('積分','外觀','排行榜','左鍵','右鍵'):
            self.assertIn(expected,text)
        self.assertNotIn('Left-click',text)

    def test_pet_xp_tooltip_displays_translated_labels_and_controls(self):
        code=(ROOT/'UI/PetXPBar.lua').read_text(encoding='utf-8-sig')
        snippet=code[code.index('local function ShowTooltip'):code.index('---------------------------------------------------------------------------\n-- Position')]
        self.lua.execute("""local ns=...; local L=ns.L; local X={db={locked=false}}
            local state={preview=false,name='蒂法',level=23,cur=52,max=7350,session=0}
            local function Fmt(x) return tostring(x) end
        """+snippet+"\nShowTooltip({})",self.ns)
        text=' '.join(str(v) for v in self.lua.globals().lines.values())
        for expected in ('等級','經驗','下一級','拖曳','右鍵'):
            self.assertIn(expected,text)
        self.assertNotIn('Experience',text)

if __name__=='__main__': unittest.main()
