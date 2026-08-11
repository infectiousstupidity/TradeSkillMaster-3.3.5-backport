#!/bin/sh
echo "🔍 Running WoW Addon Code Quality Checks..."

# 1. Syntax check (luac -p)
for file in ; do
    if [ -f "" ]; then
        luac -p ""
        if [ 1 -ne 0 ]; then
            echo "❌ Syntax error in "
            exit 1
        fi
    fi
done

# 2. Luacheck if available
if command -v luacheck >/dev/null 2>&1; then
    luacheck 
    if [ 1 -ne 0 ]; then
        echo "❌ Luacheck quality check failed!"
        exit 1
    fi
fi

echo "✅ All code checks passed!"
exit 0
