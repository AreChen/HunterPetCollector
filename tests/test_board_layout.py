import os, sys, unittest
from pathlib import Path
if os.environ.get('HPC_TEST_DEPS'): sys.path.insert(0, os.environ['HPC_TEST_DEPS'])
from lupa import LuaRuntime
ROOT=Path(__file__).resolve().parents[1]

class BoardLayoutTests(unittest.TestCase):
    def test_leaderboard_header_is_bounded_and_localized(self):
        lua=LuaRuntime(unpack_returned_tuples=True)
        lua.execute("""
          function GetLocale() return 'zhTW' end
          objects={}; local function make(kind)
            local o={kind=kind,points={}}; table.insert(objects,o)
            function o:SetPoint(...) table.insert(self.points,{...}) end
            function o:SetText(v) self.text=v end
            function o:SetTextColor(...) end
            function o:SetAllPoints(...) end
            function o:SetWidth(v) self.width=v end
            function o:SetHeight(v) self.height=v end
            function o:SetWordWrap(v) self.wrap=v end
            function o:SetJustifyV(v) end
            function o:Hide() end
            function o:SetScript(...) end
            return o
          end
          function CreateFrame(...) return make('frame') end
          ns={W={Panel=function() return make('panel') end,
            Text=function() return make('text') end,
            Button=function(_, name) return make(name) end}, IsMegaServer=function() return true end}
        """)
        ns=lua.globals().ns
        for f in ('Locale/enUS.lua','Locale/zhTW.lua'):
            lua.execute('return function(...) '+(ROOT/f).read_text(encoding='utf-8-sig')+'\nend')('addon',ns)
        code=(ROOT/'UI/Board.lua').read_text(encoding='utf-8-sig')
        snippet=code[code.index('function ns.BuildBoard(parent)'):code.index('    -- column header')]
        lua.execute('local ns=...; local W,L=ns.W,ns.L; local page,list,mine,info,filterBtns\n'+snippet+'\nend\nns.BuildBoard({})',ns)
        text=[obj for obj in lua.globals().objects.values() if obj.kind=='text']
        title,info,mine=text[:3]
        self.assertIn('排行榜', title.text)
        self.assertIn('公會', info.text)
        self.assertTrue(info.wrap)
        self.assertGreater(info.height, 20)
        self.assertIn('TOPRIGHT', [p[1] for p in info.points.values()])
        self.assertIn('TOPRIGHT', [p[1] for p in title.points.values()])
        self.assertIsNotNone(mine.width)

if __name__=='__main__': unittest.main()
