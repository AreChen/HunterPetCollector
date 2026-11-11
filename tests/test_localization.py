import os, sys, unittest
from pathlib import Path
if os.environ.get('HPC_TEST_DEPS'):
    sys.path.insert(0, os.environ['HPC_TEST_DEPS'])
from lupa import LuaRuntime
ROOT = Path(__file__).resolve().parents[1]

class LocalizationTests(unittest.TestCase):
    def load(self, locale):
        lua = LuaRuntime(unpack_returned_tuples=True)
        lua.globals().GetLocale = lambda: locale
        ns = lua.table()
        for file in ('Locale/enUS.lua', 'Locale/zhCN.lua'):
            lua.execute('return function(...) ' + (ROOT / file).read_text(encoding='utf-8-sig') + '\nend')('HunterPetCollector', ns)
        return ns.L

    def test_english_and_fallback(self):
        for locale in ('enUS', 'frFR'):
            self.assertEqual(self.load(locale)['Collection'], 'Collection')
            self.assertEqual(self.load(locale)['Not translated'], 'Not translated')

    def test_chinese_and_fallback(self):
        lang = self.load('zhCN')
        self.assertEqual(lang['Collection'], '收藏')
        self.assertEqual(lang['Not translated'], 'Not translated')

    def test_toc_loads_locales_before_core(self):
        for file in ROOT.glob('*.toc'):
            text = file.read_text(encoding='utf-8-sig')
            self.assertLess(text.index('Locale\\enUS.lua'), text.index('Locale\\zhCN.lua'))
            self.assertLess(text.index('Locale\\zhCN.lua'), text.index('Core.lua'))


class OptionsTests(unittest.TestCase):
    def test_open_options_selects_main_window_page(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        ns = lua.table()
        ns.W = lua.table()
        ns.On = lambda *args: None
        selected = []
        ns.ToggleMain = lambda tab: selected.append(tab)
        code = (ROOT / 'UI/Options.lua').read_text(encoding='utf-8-sig')
        lua.execute('return function(...) ' + code + '\nend')('HunterPetCollector', ns)
        ns.OpenOptions()
        self.assertEqual(selected, ['options'])

class SourceTests(unittest.TestCase):
    def test_all_lua_sources_compile(self):
        lua = LuaRuntime(unpack_returned_tuples=True)
        compile_source = lua.eval('function(code, name) local f, e = load(code, name); return f ~= nil, e end')
        for path in ROOT.rglob('*.lua'):
            ok, error = compile_source(path.read_text(encoding='utf-8-sig'), str(path))
            self.assertTrue(ok, error)

    def test_all_toc_paths_exist(self):
        for toc in ROOT.glob('*.toc'):
            for line in toc.read_text(encoding='utf-8-sig').splitlines():
                line = line.strip()
                if line and not line.startswith('#'):
                    self.assertTrue((ROOT / line.replace('\\', '/')).is_file(), (toc, line))

if __name__ == '__main__': unittest.main()
