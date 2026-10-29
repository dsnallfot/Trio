import json,copy,subprocess,os,sys,argparse
from pathlib import Path
r=Path(__file__).resolve().parents[1];sys.path.insert(0,str(r/'scripts'))
parser=argparse.ArgumentParser(description="Extended synthetic JS/Swift dosing contracts; run test-swift-oref.py first.")
parser.add_argument('--work-dir',type=Path,required=True)
parser.add_argument('--report',type=Path,required=True)
opts=parser.parse_args()

import importlib
h=importlib.import_module('test-oref-replay');sw=importlib.import_module('test-swift-oref')
base=json.load(open(r/'TrioTests/OrefReplay/fixtures/meal-smb.input.json'))
cases=[]
for name,oref,prefs,extra in [
 ('override-isf-cr',{'useOverride':True,'overridePercentage':150,'isfAndCr':True},{},{}),
 ('override-isf',{'useOverride':True,'overridePercentage':130,'isf':True},{},{}),
 ('override-cr',{'useOverride':True,'overridePercentage':80,'cr':True},{},{}),
 ('override-target',{'useOverride':True,'overrideTarget':120},{},{}),
 ('override-smb-limits',{'useOverride':True,'advancedSettings':True,'smbMinutes':17,'uamMinutes':13},{},{}),
 ('smb-day-off',{'smbIsScheduledOff':True,'start':10,'end':13},{},{}),
 ('smb-night-on',{'smbIsScheduledOff':True,'start':22,'end':6},{},{}),
 ('smb-all-off',{'smbIsScheduledOff':True,'start':0,'end':0},{},{}),
 ('dynamic-high-target',{'useOverride':True,'overrideTarget':125},{'useNewFormula':True,'high_temptarget_raises_sensitivity':True},{}),
 ('dynamic-short-history',{}, {'useNewFormula':True}, {'history':base['history'][:10]}),
 ('dynamic-no-history',{}, {'useNewFormula':True}, {'history':[]}),
 ('exercise-target',{}, {'exercise_mode':True}, {'tempTargets':[{'_id':'synthetic-target','created_at':'2026-02-12T10:50:00Z','duration':60,'targetTop':140,'targetBottom':140,'enabled':True}]}),
 ('low-target',{}, {'low_temptarget_lowers_sensitivity':True}, {'tempTargets':[{'_id':'synthetic-target','created_at':'2026-02-12T10:50:00Z','duration':60,'targetTop':80,'targetBottom':80,'enabled':True}]})]:
 f=copy.deepcopy(base);f['name']=name;f['oref2'].update(oref);f['preferences'].update(prefs);f.update(extra);cases.append(f)
subprocess.run(['xcrun','swiftc',str(r/'scripts/oref-replay/main.swift'),'-o',str(opts.work_dir/'js-replay')],check=True)
rows=[]
for f in cases:
 outputs={}
 for engine in ['js','swift']:
  out={}
  for m in h.MODULES:
   args=h.arguments(f,out,m)
   q={'clock':f['clock'],'timezoneOffsetMinutes':f['timezoneOffsetMinutes'],'module':m,'arguments':args if engine=='js' else [json.dumps(a) for a in args]}
   cmd=[str(opts.work_dir/'js-replay'),str(r)] if engine=='js' else [str(opts.work_dir/'.build/debug/OrefReplay')]
   p=subprocess.run(cmd,input=json.dumps(q),text=True,capture_output=True,env={**os.environ,'TZ':f['timezone']},timeout=30)
   if p.returncode:out[m]={'error':p.stderr};break
   out[m]=json.loads(p.stdout)
  outputs[engine]=out
 a=outputs['swift'].get('determineBasal',{});e=outputs['js'].get('determineBasal',{})
 dif=sw.differences({k:e.get(k,'ABSENT') for k in sw.DOSE_FIELDS},{k:a.get(k,'ABSENT') for k in sw.DOSE_FIELDS})
 errors=[{'engine':engine,'module':mod,'error':value['error']} for engine,out in outputs.items() for mod,value in out.items() if isinstance(value,dict) and 'error' in value]
 row={'case':f['name'],'differences':dif,'errors':errors};rows.append(row);print(f['name'], 'PASS' if not dif and not errors and a and e else row)
opts.report.write_text(json.dumps(rows,indent=2)+'\n')
assert all(not row['differences'] and not row['errors'] for row in rows), rows
