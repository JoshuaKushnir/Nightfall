import os
import re

# 1. Map all lua files to their paths from src root
file_paths = {}
for root, _, files in os.walk("src"):
    for f in files:
        if f.endswith(".lua"):
            mod_name = f[:-4]
            full_path = os.path.join(root, f).replace("\\", "/")
            file_paths[mod_name] = full_path

# Expected new paths
# Services -> ServerScriptService.Server.services.folder.mod
# Controllers -> Players.LocalPlayer.PlayerScripts.Client.controllers.folder.mod (Wait, they usually require via relative paths like script.Parent.Parent.controllers.combat.CombatController or script.Parent.CombatController)
# Modules -> ReplicatedStorage.Shared.modules.folder.mod

services_dir = "src/server/services"
services_map = {}
for root, _, files in os.walk(services_dir):
    for f in files:
        if f.endswith(".lua"):
            mod = f[:-4]
            rel = os.path.relpath(root, services_dir).replace("\\", "/")
            services_map[mod] = rel if rel != "." else ""

controllers_dir = "src/client/controllers"
controllers_map = {}
for root, _, files in os.walk(controllers_dir):
    for f in files:
        if f.endswith(".lua"):
            mod = f[:-4]
            rel = os.path.relpath(root, controllers_dir).replace("\\", "/")
            controllers_map[mod] = rel if rel != "." else ""

modules_dir = "src/shared/modules"
modules_map = {}
for root, _, files in os.walk(modules_dir):
    for f in files:
        if f.endswith(".lua"):
            mod = f[:-4]
            rel = os.path.relpath(root, modules_dir).replace("\\", "/")
            modules_map[mod] = rel if rel != "." else ""

def fix_content(content, filepath):
    # Fix ReplicatedStorage.Shared.modules.X
    def repl_module(m):
        mod = m.group(1)
        if mod in modules_map and modules_map[mod]:
            return f"ReplicatedStorage.Shared.modules.{modules_map[mod]}.{mod}"
        return m.group(0)
    
    content = re.sub(r'ReplicatedStorage\.Shared\.modules\.(\w+)', repl_module, content)
    
    # Also handle Shared.modules.X
    def repl_shared_module(m):
        mod = m.group(1)
        if mod in modules_map and modules_map[mod]:
            return f"Shared.modules.{modules_map[mod]}.{mod}"
        return m.group(0)
        
    content = re.sub(r'Shared\.modules\.(\w+)', repl_shared_module, content)

    # Fix ServerScriptService.Server.services.X
    def repl_service(m):
        mod = m.group(1)
        if mod in services_map and services_map[mod]:
            return f"ServerScriptService.Server.services.{services_map[mod]}.{mod}"
        return m.group(0)

    content = re.sub(r'ServerScriptService\.Server\.services\.(\w+)', repl_service, content)

    # Fix game:GetService("ServerScriptService").Server.services.X
    def repl_service_get(m):
        mod = m.group(1)
        if mod in services_map and services_map[mod]:
            return f"game:GetService(\"ServerScriptService\").Server.services.{services_map[mod]}.{mod}"
        return m.group(0)

    content = re.sub(r'game:GetService\("ServerScriptService"\)\.Server\.services\.(\w+)', repl_service_get, content)
    
    # Fix script.Parent.X where X is a controller or service AND we know we are inside controllers/services folder
    if "src/server/services" in filepath:
        # relative require for services
        def repl_rel_service(m):
            mod = m.group(1)
            if mod in services_map and services_map[mod]:
                # figure out relative path from current service to target service
                curr_folder = os.path.basename(os.path.dirname(filepath))
                target_folder = services_map[mod]
                if curr_folder == target_folder:
                    return f"script.Parent.{mod}"
                else:
                    return f"script.Parent.Parent.{target_folder}.{mod}"
            return m.group(0)
        content = re.sub(r'script\.Parent\.(\w+)', repl_rel_service, content)

    if "src/client/controllers" in filepath:
        # relative require for controllers
        def repl_rel_controller(m):
            mod = m.group(1)
            if mod in controllers_map and controllers_map[mod]:
                curr_folder = os.path.basename(os.path.dirname(filepath))
                target_folder = controllers_map[mod]
                if curr_folder == target_folder:
                    return f"script.Parent.{mod}"
                else:
                    return f"script.Parent.Parent.{target_folder}.{mod}"
            return m.group(0)
        content = re.sub(r'script\.Parent\.(\w+)', repl_rel_controller, content)
        
        # also handle script.Parent.Parent.controllers.X which might exist in ui/
        def repl_rel_controller_parent(m):
            mod = m.group(1)
            if mod in controllers_map and controllers_map[mod]:
                return f"script.Parent.Parent.controllers.{controllers_map[mod]}.{mod}"
            return m.group(0)
        content = re.sub(r'script\.Parent\.Parent\.controllers\.(\w+)', repl_rel_controller_parent, content)

    return content

for root, _, files in os.walk("src"):
    for f in files:
        if f.endswith(".lua"):
            path = os.path.join(root, f)
            with open(path, 'r', encoding='utf-8') as file:
                content = file.read()
            
            new_content = fix_content(content, path.replace("\\", "/"))
            
            if content != new_content:
                with open(path, 'w', encoding='utf-8') as file:
                    file.write(new_content)

print("Done")
