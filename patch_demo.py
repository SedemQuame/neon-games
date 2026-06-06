import os
import re

lib_dir = "game_trader_app/lib/screens/game_screens"
for root, _, files in os.walk(lib_dir):
    for f in files:
        if not f.endswith(".dart"): continue
        path = os.path.join(root, f)
        with open(path) as f_in:
            content = f_in.read()

        # Find "if (_playMode.isDemo) {"
        # We need to insert the balance check right after it.
        # But wait, stake variable name is different in each file!
        # It's usually `stakeAmount` or `_stakeAmount` or `_currentStake` etc.
        # We can look for `stakeUsd:` inside the `buildDemoGameResult` call to find the variable.

        match = re.search(r'buildDemoGameResult\([^)]*stakeUsd:\s*([a-zA-Z0-9_]+)', content)
        if match:
            stake_var = match.group(1)
            
            # 1. Insert the deduction logic
            deduction = f"""
      final session = context.read<SessionManager>();
      if (!session.deductDemoBalance({stake_var})) {{
        showGameMessage(context, 'Insufficient demo balance.');
        return;
      }}"""
            # Replace "if (_playMode.isDemo) {" with "if (_playMode.isDemo) {" + deduction
            content = content.replace("if (_playMode.isDemo) {", "if (_playMode.isDemo) {" + deduction)

            # 2. Add winnings logic. We need to find the `onGameResult(` or `_handleGameResult(` that takes `buildDemoGameResult` directly, or the variable.
            # Some games do `onGameResult(buildDemoGameResult(...))`
            # We can replace `onGameResult(buildDemoGameResult` with
            # `final res = buildDemoGameResult...; if (res.winAmountUsd > 0) context.read<SessionManager>().addDemoWinnings(res.winAmountUsd); onGameResult(res);`
            
            # Simple regex to replace nested call
            # `(onGameResult|_handleGameResult)\(\s*buildDemoGameResult\((.*?)\)\s*,?\s*\);`
            # Note: `(.*?)` across newlines requires re.DOTALL
            def repl(m):
                func = m.group(1)
                args = m.group(2)
                return f"""final demoRes = buildDemoGameResult({args});
      if (demoRes.winAmountUsd > 0) {{
        context.read<SessionManager>().addDemoWinnings(demoRes.winAmountUsd);
      }}
      {func}(demoRes);"""
            
            content = re.sub(r'(onGameResult|_handleGameResult)\(\s*buildDemoGameResult\((.*?)\)\s*,?\s*\);', repl, content, flags=re.DOTALL)
            
            with open(path, "w") as f_out:
                f_out.write(content)
            print(f"Patched {f}")
