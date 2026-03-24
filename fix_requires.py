import re
import sys
import os

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find top-level requires to script.Parent
    pattern = re.compile(r'^local\s+([A-Za-z0-9_]+)\s*=\s*require\(script\.Parent\.([A-Za-z0-9_]+)\)', re.MULTILINE)
    
    matches = pattern.findall(content)
    if not matches:
        return
        
    print(f"Fixing {filepath}...")
    
    # Replace top level with nil
    for var, mod in matches:
        content = re.sub(r'^local\s+' + var + r'\s*=\s*require\(script\.Parent\.' + mod + r'\)', f'local {var}: any = nil', content, flags=re.MULTILINE)
        
    # Inject in Init
    init_pattern = re.compile(r'(function\s+[A-Za-z0-9_]+:Init\s*\((.*?)\)\n)')
    
    inject_code = ""
    for var, mod in matches:
        inject_code += f"\n    if dependencies and dependencies.{mod} then\n"
        inject_code += f"        {var} = dependencies.{mod}\n"
        inject_code += f"    else\n"
        inject_code += f"        {var} = require(script.Parent.{mod})\n"
        inject_code += f"    end\n"
        
    def replace_init(m):
        header = m.group(1)
        params = m.group(2)
        if 'dependencies' not in params:
            header = header.replace('()', '(dependencies)')
        return header + inject_code
        
    content = init_pattern.sub(replace_init, content)
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(content)

files = [
    'src/server/services/AspectService.lua',
    'src/server/services/CombatService.lua',
    'src/server/services/HollowedService.lua',
    'src/server/services/InventoryService.lua',
    'src/server/services/ProgressionService.lua',
    'src/server/services/TrainingToolService.lua'
]

for f in files:
    process_file(f)

