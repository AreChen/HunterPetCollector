import os, sys, unittest
from pathlib import Path
if os.environ.get("HPC_TEST_DEPS"):
    sys.path.insert(0, os.environ["HPC_TEST_DEPS"])
from lupa import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]

class OfficialNamesTests(unittest.TestCase):
    def setUp(self):
        self.lua = LuaRuntime(unpack_returned_tuples=True)
        self.lua.execute("""
            locale = 'zhTW'; function GetLocale() return locale end
            timers = {}; C_Timer = {After=function(delay, fn) table.insert(timers, fn) end}
            function runTimer() local fn=table.remove(timers, 1); if fn then fn() end end
            Enum={TooltipDataType={Unit=2}}; UIParent={}; hooks={}
            TooltipDataProcessor={AddTooltipPostCall=function(_, cb) table.insert(hooks, cb) end}
            tooltip={Show=function() end, SetOwner=function() end, SetHyperlink=function(self, link) self.link=link end}
            function CreateFrame(kind) if kind=='GameTooltip' then return tooltip end
                observer={ RegisterEvent=function() end, SetScript=function(self, _, fn) self.event=fn end }; return observer end
            function deliver(id, name)
                for _, cb in ipairs(hooks) do cb(tooltip, {guid='Creature-0-0-0-0-'..id..'-0',lines={{leftText=name}}}) end
            end
            ns={flavor='forever',db={},lookList={{id=1,name='fallback',sources={{npc=4425,name='fallback',englishName='Blind Hunter'}}}}}
            ns.SafeGUID=function() return 'Creature-0-0-0-0-4425-0' end; UnitName=function() return '目標官方名稱' end; ns.npcToLook={[4425]=ns.lookList[1]}
            ns.IsSecret=function() return false end; ns.NPCIDFromGUID=function(g) return tonumber(g:match('Creature%-0%-0%-0%-0%-(%d+)%-0')) end
        """)
        self.ns=self.lua.globals().ns
        self.lua.execute('return function(...) '+(ROOT/'Locale/Data.lua').read_text(encoding='utf-8-sig')+'\nend')('addon',self.ns)
        path=ROOT/'Locale/OfficialNames.lua'
        if path.exists():
            self.lua.execute('return function(...) '+path.read_text(encoding='utf-8-sig')+'\nend')('addon',self.ns)

    def test_official_result_is_cached_and_updates_look(self):
        self.assertIsNotNone(self.ns.RequestOfficialNPCName)
        self.ns.RequestOfficialNPCName(4425)
        self.lua.globals().deliver(4425, '官方獵手')
        self.assertEqual(self.ns.LocalizeNPC(4425,'fallback'), '官方獵手')
        self.assertEqual(self.ns.lookList[1].name,'官方獵手')
        self.assertEqual(self.ns.lookList[1].sources[1].englishName,'Blind Hunter')

    def test_failed_lookup_does_not_replace_fallback_and_queue_continues(self):
        self.assertIsNotNone(self.ns.RequestOfficialNPCName)
        self.ns.RequestOfficialNPCName(4425)
        self.ns.RequestOfficialNPCName(4426)
        self.lua.globals().runTimer(); self.lua.globals().runTimer(); self.lua.globals().runTimer()
        self.assertEqual(self.ns.LocalizeNPC(4425,'fallback'),'fallback')
        self.lua.globals().deliver(4426,'第二隻')
        self.assertEqual(self.ns.LocalizeNPC(4426,'fallback'),'第二隻')

    def test_observed_target_overrides_cached_translation(self):
        self.ns.RequestOfficialNPCName(4425)
        self.lua.globals().deliver(4425, '舊名稱')
        self.lua.execute("observer.event(observer, 'PLAYER_TARGET_CHANGED')")
        self.assertEqual(self.ns.LocalizeNPC(4425, 'fallback'), '目標官方名稱')
        self.assertEqual(self.ns.lookList[1].name, '目標官方名稱')

    def test_failed_api_availability_preserves_existing_fallback(self):
        self.lua.execute('TooltipDataProcessor = nil')
        self.ns.RequestOfficialNPCName(4425)
        self.assertEqual(self.ns.LocalizeNPC(4425, 'fallback'), 'fallback')

    def test_wrong_guid_is_rejected_and_locale_isolated(self):
        self.assertIsNotNone(self.ns.RequestOfficialNPCName)
        self.ns.RequestOfficialNPCName(4425)
        self.lua.globals().deliver(4426,'錯誤名稱')
        self.assertEqual(self.ns.LocalizeNPC(4425,'fallback'),'fallback')
        self.lua.globals().deliver(4425,'官方獵手')
        self.lua.globals().locale='zhCN'
        self.assertEqual(self.ns.LocalizeNPC(4425,'fallback'),'fallback')
        self.lua.globals().locale='zhTW'
        self.ns.flavor='mop'
        self.assertEqual(self.ns.LocalizeNPC(4425,'fallback'),'fallback')

if __name__=='__main__': unittest.main()
