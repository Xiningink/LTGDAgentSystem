import json, sys
import solve as S

data = json.load(open('../game/assets/levels.json'))
ids = sys.argv[1:] or [l['id'] for l in data['levels']]
for lv in data['levels']:
    if lv['id'] not in ids: continue
    sol, _ = S.solve(lv)
    p = S.parse_level(lv)
    state = {'tiles':p['tiles'],'player':p['player'],'polarity':p['polarity'],'items':dict(p['items']),'inert':set()}
    print("="*70)
    print(lv['id'], lv['name'], "par", len(sol), sol)
    for y in range(p['height']):
        print('  '+''.join(p['tiles'][(x,y)] for x in range(p['width'])))
    prev_gates = S.compute_gates(state['tiles'],state['items'],state['player'],state['inert'])
    for i,ch in enumerate(sol):
        old_items = dict(state['items']); old_pol = state['polarity']; old_inert=set(state['inert'])
        state = S.step(state, S.DIRS[ch])
        notes=[]
        if state['polarity']!=old_pol: notes.append("POLARITY->%s"%state['polarity'])
        if state['inert']!=old_inert: notes.append("HAZARD CLEARED %s"%(state['inert']-old_inert))
        moved={k:v for k,v in state['items'].items() if old_items.get(k)!=v}
        gone=set(old_items)-set(state['items']); new=set(state['items'])-set(old_items)
        if gone: notes.append("DESTROYED %s"%gone)
        if moved: notes.append("ITEMS %s"%moved)
        g=S.compute_gates(state['tiles'],state['items'],state['player'],state['inert'])
        for k in g:
            if g[k]!=prev_gates.get(k): notes.append("GATE %s %s"%(k,"OPEN" if g[k] else "SHUT"))
        prev_gates=g
        note = ("  <- "+", ".join(notes)) if notes else ""
        print("  %2d %s  player%s%s"%(i+1,ch,state['player'],note))
