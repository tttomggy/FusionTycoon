import re,glob,sys
theme=open('src/ReplicatedStorage/Shared/Modules/UITheme.lua').read()
# collect table blocks: UITheme.X = { ... } keys
defined=set(re.findall(r'^UITheme\.(\w+)\s*=',theme,re.M))
blocks={}
for m in re.finditer(r'^UITheme\.(\w+)\s*=\s*\{',theme,re.M):
    name=m.group(1); i=m.end(); depth=1; j=i
    while depth and j<len(theme):
        if theme[j]=='{':depth+=1
        elif theme[j]=='}':depth-=1
        j+=1
    body=theme[i:j]
    keys=set(re.findall(r'^\t(\w+)\s*=',body,re.M))
    blocks[name]=keys
miss=[]
for f in glob.glob('src/**/*.lua',recursive=True):
    s=open(f).read()
    alias={a:b for a,b in re.findall(r'local (\w+)\s*=\s*UITheme\.(\w+)\b',s)}
    for m in re.finditer(r'UITheme\.(\w+)\.(\w+)',s):
        t,k=m.groups()
        if t in blocks and k not in blocks[t]: miss.append((f,s[:m.start()].count('\n')+1,f'UITheme.{t}.{k}'))
    for a,t in alias.items():
        if t not in blocks: continue
        for m in re.finditer(r'\b'+a+r'\.(\w+)',s):
            k=m.group(1)
            if k not in blocks[t]: miss.append((f,s[:m.start()].count('\n')+1,f'{a}.{k} (UITheme.{t})'))
for x in sorted(set(miss)): print(*x)
