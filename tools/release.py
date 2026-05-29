import sys
import re
import subprocess
from pathlib import Path

def run_cmd(cmd):
    print(f"Running: {' '.join(cmd)}")
    subprocess.run(cmd, check=True)

def main():
    if len(sys.argv) != 2:
        print("Usage: python release.py <new_version>")
        sys.exit(1)

    new_version = sys.argv[1]
    
    # Path to _meta.lua relative to this script's location
    meta_path = Path(__file__).parent.parent / "xray.koplugin" / "_meta.lua"
    
    if not meta_path.exists():
        print(f"Error: Could not find {meta_path}")
        sys.exit(1)
        
    print(f"Updating version to {new_version} in {meta_path.name}")
    content = meta_path.read_text(encoding="utf-8")
    
    # Find and replace the version string
    new_content, count = re.subn(r'version\s*=\s*"[^"]+"', f'version = "{new_version}"', content)
    
    if count == 0:
        print("Error: Could not find version string in _meta.lua")
        sys.exit(1)
        
    version_changed = (content != new_content)
    
    if version_changed:
        meta_path.write_text(new_content, encoding="utf-8")
        print("Version updated successfully.")
    else:
        print("Version is already set to the target version in _meta.lua.")
    
    # Git operations
    print("Executing git commands...")
    try:
        if version_changed:
            run_cmd(["git", "add", str(meta_path.resolve())])
            run_cmd(["git", "commit", "-m", f"Release {new_version}"])
            
        # Check if tag already exists locally
        tag_check = subprocess.run(["git", "tag", "-l", new_version], capture_output=True, text=True)
        tag_exists = new_version in tag_check.stdout.splitlines()
        if not tag_exists:
            run_cmd(["git", "tag", new_version])
        else:
            print(f"Tag {new_version} already exists locally. Skipping local tag creation.")
            
        # Push commit and/or tag in a single git push command to avoid entering passphrase twice
        push_cmd = ["git", "push", "origin"]
        if version_changed:
            push_cmd.extend(["HEAD", new_version])
        else:
            push_cmd.append(new_version)
            
        run_cmd(push_cmd)
        print(f"\n✅ Release {new_version} completed and pushed successfully!")
    except subprocess.CalledProcessError as e:
        print(f"Error during git operations: {e}")
        sys.exit(1)

if __name__ == "__main__":
    main()
