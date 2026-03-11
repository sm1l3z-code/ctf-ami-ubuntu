#!/bin/bash

# 2. Clone the repo (using --depth 1 to keep it fast)
git clone --depth 1 git@github.com:sm1l3z-code/htb-mcp.git temp_clone

# 3. Create the tarball (git archive excludes the .git folder automatically)
cd temp_clone
git archive --format=tar.gz -o ../artifacts/src_archive.tar.gz HEAD

# 4. Clean up the cloned folder
cd ..
rm -rf temp_clone

