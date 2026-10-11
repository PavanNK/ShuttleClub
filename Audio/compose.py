"""Original club music and effects, synthesized from oscillators and seeded noise.
No imported recordings, samples, MIDI files or model services. See LICENSE.txt.
"""
from pathlib import Path
import numpy as np
import wave,json
RATE=44100
OUT=Path(__file__).resolve().parents[1]/'Resources'/'Audio'
OUT.mkdir(parents=True,exist_ok=True)
rng=np.random.default_rng(20261011)
metadata={}
def write(name,data):
    data=np.asarray(data)
    peak=np.max(np.abs(data)); data=data*(0.86/max(peak,0.001))
    pcm=(data*32767).astype('<i2')
    with wave.open(str(OUT/(name+'.wav')),'wb') as f:
        f.setnchannels(1 if data.ndim==1 else data.shape[1]);f.setsampwidth(2);f.setframerate(RATE);f.writeframes(pcm.tobytes())
    metadata[name]={'seconds':round(len(data)/RATE,4),'channels':1 if data.ndim==1 else data.shape[1],'peak':round(float(np.max(np.abs(data))),4),'rms_db':round(float(20*np.log10(max(1e-8,np.sqrt(np.mean(data**2))))),2)}
def note(midi,seconds,kind='pluck'):
    t=np.arange(int(seconds*RATE))/RATE;hz=440*2**((midi-69)/12)
    attack=1-np.exp(-t/0.004)
    if kind=='bass': return np.sin(2*np.pi*hz*t)*np.exp(-t/0.30)*attack+.12*np.sin(4*np.pi*hz*t)*np.exp(-t/.18)*attack
    return attack*(np.sin(2*np.pi*hz*t)*np.exp(-t/.38)+.24*np.sin(2*np.pi*hz*2.002*t)*np.exp(-t/.22)+.12*np.sin(2*np.pi*hz*3.99*t)*np.exp(-t/.09))
beat=60/110;length=int(beat*64*RATE);song=np.zeros((length,2))
def add(data,at,level=.1,pan=0):
    start=int(at*RATE);index=(np.arange(len(data))+start)%length
    song[index,0]+=data*level*np.sqrt((1-pan)/2);song[index,1]+=data*level*np.sqrt((1+pan)/2)
chords=[[53,57,60,64],[48,52,55,62],[45,48,52,55],[43,50,55,59]]
melody=[[76,79,81,79,76,74],[74,76,79,76,72,74],[72,76,79,81,79,76],[74,79,83,81,79,74]]
for bar in range(16):
    root=chords[bar%4][0]-12
    for b in [0,1.5,2,3.5]: add(note(root if b in [0,2] else root+7,.45,'bass'),(bar*4+b)*beat,.29)
    for k,midi in enumerate(chords[bar%4]): add(note(midi+12,1.2),(bar*4+k*.025)*beat,.07,(-1)**k*.3)
    for k,midi in enumerate(melody[bar%4]):
        timing=[.0,.75,1.5,2.25,3,3.5][k]
        if bar>=8 and k==2: midi+=12
        voice=note(midi,.7)
        add(voice,(bar*4+timing)*beat,.13,.25*np.sin(bar+k))
        add(voice,(bar*4+timing+.5)*beat,.026,-.25)
    for b in range(4):
        t=np.arange(int(.19*RATE))/RATE
        kick=np.sin(2*np.pi*(52*t+17*(1-np.exp(-t/0.025))))*np.exp(-t/.048)*(1-np.exp(-t/.001))
        add(kick,(bar*4+b)*beat,.22)
        if b in [1,3]:
            t=np.arange(int(.11*RATE))/RATE;n=rng.normal(0,1,len(t));clap=np.diff(n,prepend=0)*np.exp(-t/.027)*(1-np.exp(-t/.0015))
            add(clap,(bar*4+b)*beat,.037,.05)
    for tick in range(8):
        t=np.arange(int(.05*RATE))/RATE;n=rng.normal(0,1,len(t));shaker=np.diff(n,prepend=0)*np.exp(-t/.009)*(1-np.exp(-t/.001))
        add(shaker,(bar*4+tick/2)*beat,.009 if tick%2==0 else .014,(-1)**tick*.4)
song=np.tanh(song*1.1)
write('ClubLoop',song)
# A crisp cork/string impact with short resonances, not a generic musical beep.
for variant in [1,2]:
    t=np.arange(int(.14*RATE))/RATE
    noise=rng.normal(0,1,len(t));snap=np.diff(noise,prepend=0)*np.exp(-t/.006)
    modes=sum(weight*np.sin(2*np.pi*freq*t)*np.exp(-t/decay) for weight,freq,decay in [(1,440+variant*35,.027),(.45,1160+variant*70,.022),(.22,2300,.013)])
    write('Hit'+str(variant),(snap*.18+modes*.5)*(1-np.exp(-t/.0002)))
t=np.arange(int(.28*RATE))/RATE
write('Net',rng.normal(0,1,len(t))*np.exp(-t/.04)*.14+np.sin(2*np.pi*88*t)*np.exp(-t/.075)*.28)
write('Serve',rng.normal(0,1,len(t))*np.exp(-((t-.09)/.047)**2)*.13+np.sin(2*np.pi*540*t)*np.exp(-t/.04)*.10)
t=np.arange(int(.16*RATE))/RATE
write('Step',rng.normal(0,1,len(t))*np.exp(-t/.012)*.18+np.sin(2*np.pi*105*t)*np.exp(-t/.024)*.35)
def phrase(name,notes,gap,duration):
    data=np.zeros(int(duration*RATE))
    for i,midi in enumerate(notes):
        voice=note(midi,.4);start=int(i*gap*RATE);end=min(len(data),start+len(voice));data[start:end]+=voice[:end-start]
    write(name,data)
phrase('Win',[72,76,79,84],.11,.9)
phrase('Miss',[64,60],.11,.5)
phrase('Target',[79,84,88],.065,.65)
phrase('Menu',[72,79],.038,.3)
phrase('Select',[79,84],.045,.3)
phrase('Pause',[76,72],.045,.3)
(OUT/'AudioManifest.json').write_text(json.dumps({'source':'Original oscillator/noise synthesis','licence':'CC0-1.0','rate':RATE,'bpm':110,'seed':20261011,'files':metadata},indent=2))
assert all(v['peak']<1 for v in metadata.values())
print(json.dumps(metadata,indent=2))
