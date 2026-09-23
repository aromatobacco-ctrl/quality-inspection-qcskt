'use strict';
  const $=id=>document.getElementById(id);
  const BRAND_SPECS={ARB12:{weight:[1.10,1.20],diameter:[7.42,7.52],pd:[90,100],vent:[20,30]},ARB16:{weight:[1.10,1.20],diameter:[7.42,7.52],pd:[90,100],vent:[20,30]},AMT:{weight:[.96,1.06],diameter:[6.92,7.02],pd:[115,125],vent:[23,33]},AMB:{weight:[.96,1.06],diameter:[6.92,7.02],pd:[115,125],vent:[23,33]},ARM:{weight:[.90,1.00],diameter:[6.92,7.02],pd:[105,115],vent:[27,37]}};
  const PHYSICAL={weight:{label:'Berat',unit:'g',step:'.001'},diameter:{label:'Diameter',unit:'mm',step:'.001'},pd:{label:'Pressure Drop',unit:'mmH₂O',step:'.01'},vent:{label:'Ventilasi',unit:'%',step:'.01'}};
  const MAKER_VISUAL=['Kemulusan','Panjang Cigarette','Ring','Pot Cig','Pot Fil','Lip CP','Lip CTP','Kropos','Gembos','Flaging','Blk. Ring','Cig non Filt','Spotting'];
  const PACKER_VISUAL=['Kode Produksi','Smiling Pack','Top Flip Nguping','Scratch','Inner Frame','Embos','Lipt. Foil','Posisi Lem','Jumlah Cigarette','Pita Cukai','Tear Tape OPP','Access','Lipt OPP','MOP Berkerut','Posisi Pack','Teartape MOP','Lipt MOP','Jumlah Pack'];
  const today=()=>{const d=new Date();return [d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-')};
  const dateOf=s=>new Date(`${s}T12:00:00`);
  const dateKey=d=>[d.getFullYear(),String(d.getMonth()+1).padStart(2,'0'),String(d.getDate()).padStart(2,'0')].join('-');
  const displayDate=s=>s?new Intl.DateTimeFormat('id-ID',{day:'2-digit',month:'short',year:'numeric'}).format(dateOf(s)):'—';
  const pct=(a,b)=>b?`${(100*a/b).toFixed(1)}%`:'—';
  const num=v=>v==null?'—':Number(v).toLocaleString('id-ID',{maximumFractionDigits:3});
  const safe=s=>String(s??'').replace(/[&<>"']/g,c=>({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[c]));
  const showToast=s=>{const el=$('toast');el.textContent=s;el.classList.add('show');clearTimeout(showToast.timer);showToast.timer=setTimeout(()=>el.classList.remove('show'),4400)};
  let manual=[];
  let currentUser=null,managedUsers=[],loadSequence=0,activeSession=0;
  const canWrite=()=>currentUser?.role==='INSPECTOR'||currentUser?.role==='ADMIN';
  const canDeleteRecord=r=>r.source!=='Contoh'&&(currentUser?.role==='ADMIN'||(currentUser?.role==='INSPECTOR'&&r.authorId===currentUser?.id));

  function assess(r){
    const issues=[];let inspected=0,good=0;
    if(r.type==='Maker')for(const [key,meta] of Object.entries(PHYSICAL)){
      const val=r.physical?.[key],bounds=BRAND_SPECS[r.brand]?.[key];
      if(val==null||!Number.isFinite(Number(val))||!bounds)continue;
      inspected++;if(Number(val)>=bounds[0]&&Number(val)<=bounds[1])good++;
      else issues.push(`${meta.label} ${num(val)} ${meta.unit} (target ${num(bounds[0])}–${num(bounds[1])})`);
    }
    const sample=Number(r.sample),names=r.type==='Maker'?MAKER_VISUAL:PACKER_VISUAL;
    if(Number.isInteger(sample)&&sample>0)for(const name of names){
      const v=r.visual?.[name];if(v==null||v==='')continue;
      const count=Number(v);if(!Number.isInteger(count)||count<0||count>sample)return {status:'INVALID',issues:[`${name}: jumlah baik harus 0–${sample}.`],inspected:0,good:0};
      inspected+=sample;good+=count;if(count<sample)issues.push(`${name}: ${sample-count} ${r.type==='Maker'?'batang':'pack'} out-spec`);
    }
    if(!Number.isInteger(sample)||sample<1||sample>10000)return {status:'INVALID',issues:['Jumlah sampel harus bilangan 1–10.000.'],inspected:0,good:0};
    if(!inspected&&!r.noFinding)return {status:'PENDING',issues:['Isi minimal satu parameter atau centang tidak ada temuan.'],inspected:0,good:0};
    if(!inspected&&r.noFinding){inspected=1;good=1}
    return {status:issues.length?'BAD':'GOOD',issues,inspected,good};
  }
  function demoData(){
    const out=[],base=dateOf(today()),brands=['ARM','AMB','ARB12','AMT','ARB16'];
    for(let offset=0;offset<53;offset++){
      const d=new Date(base);d.setDate(base.getDate()-offset);if(d.getDay()===0||d.getDay()===6)continue;
      const day=dateKey(d);
      brands.forEach((brand,j)=>{
        const s=BRAND_SPECS[brand],physical={};
        Object.keys(PHYSICAL).forEach((key,k)=>{const [lo,hi]=s[key],spread=hi-lo;physical[key]=Number((lo+spread*(.47+.32*Math.sin(offset*1.19+j*.81+k*.56))).toFixed(3))});
        // Beberapa titik merah dibuat melewati limit untuk contoh warning produksi.
        if((offset+j*3)%17===0)physical.pd=Number((s.pd[1]+2.5).toFixed(2));
        if((offset+j*4)%29===0)physical.diameter=Number((s.diameter[0]-.018).toFixed(3));
        const visual={};if((offset+j*5)%13===0)visual[MAKER_VISUAL[(offset+j)%MAKER_VISUAL.length]]=8;
        out.push({id:`demo-m-${offset}-${j}`,source:'Contoh',type:'Maker',date:day,time:`${String(6+(j*3)%15).padStart(2,'0')}:00`,qc:'QC Contoh',shift:j%2?'Shift 2':'Shift 1',brand,machine:`M${j+1}`,sample:10,physical,visual,noFinding:false,notes:''});
      });
      for(let p=0;p<2;p++){
        const visual={},brand=brands[(offset+p*2)%brands.length];
        if((offset+p*5)%7===0)visual[PACKER_VISUAL[(offset+p*2)%PACKER_VISUAL.length]]=8;
        else visual[PACKER_VISUAL[(offset+p*2)%PACKER_VISUAL.length]]=10;
        out.push({id:`demo-p-${offset}-${p}`,source:'Contoh',type:'Packer',date:day,time:`${p?'14':'09'}:00`,qc:'QC Contoh',shift:p?'Shift 2':'Shift 1',brand,machine:p?'P4':'P2',sample:10,physical:{},visual,noFinding:false,code:'',notes:''});
      }
    }
    return out;
  }
  const demo=demoData();
  const allRecords=()=>[$('show-demo').checked?demo:[],manual].flat().map(r=>({...r,result:assess(r)})).filter(r=>r.result.status==='GOOD'||r.result.status==='BAD').sort((a,b)=>(b.date+b.time).localeCompare(a.date+a.time));

  function periodBounds(){const period=$('period').value,selected=$('period-date').value||today();if(period==='monthly'){const month=$('period-month').value||today().slice(0,7);return {start:`${month}-01`,end:`${month}-${String(new Date(+month.slice(0,4),+month.slice(5),0).getDate()).padStart(2,'0')}`,caption:new Intl.DateTimeFormat('id-ID',{month:'long',year:'numeric'}).format(dateOf(`${month}-01`))}}if(period==='weekly'){const d=dateOf(selected),delta=(d.getDay()+6)%7;d.setDate(d.getDate()-delta);const start=dateKey(d);d.setDate(d.getDate()+4);return {start,end:dateKey(d),caption:`Minggu kerja ${displayDate(start)} – ${displayDate(dateKey(d))} (Senin–Jumat)`}}return {start:selected,end:selected,caption:displayDate(selected)}}
  function filtered(){const {start,end}=periodBounds(),brand=$('filter-brand').value,type=$('filter-station').value;return allRecords().filter(r=>r.date>=start&&r.date<=end&&(brand==='ALL'||r.brand===brand)&&(type==='ALL'||r.type===type))}
  function buildVisual(container,names,prefix){$(container).innerHTML=names.map((name,i)=>`<div class="field"><label for="${prefix}-${i}">${safe(name)}</label><input id="${prefix}-${i}" data-name="${safe(name)}" class="${prefix}-count" type="number" step="1" min="0" placeholder="Jumlah yang baik"><span class="mini-result" id="${prefix}-result-${i}">In-Spec — · Out-Spec —</span></div>`).join('')}
  function draft(type){const prefix=type==='Maker'?'maker':'packer',visual={},physical={};document.querySelectorAll(`.${prefix}-count`).forEach(el=>{if(el.value!=='')visual[el.dataset.name]=Number(el.value)});
    if(type==='Maker')for(const key of Object.keys(PHYSICAL)){const el=$(`maker-${key}`);if(el.value!=='')physical[key]=Number(el.value)}
    return {type,date:$(`${prefix}-date`).value,time:$(`${prefix}-time`).value,qc:$(`${prefix}-qc`).value.trim(),shift:$(`${prefix}-shift`).value,brand:$(`${prefix}-brand`).value,machine:$(`${prefix}-machine`).value,sample:Number($(`${prefix}-sample`).value),visual,physical,noFinding:$(`${prefix}-no-finding`).checked,notes:$(`${prefix}-notes`).value.trim(),trouble:type==='Maker'?$('maker-trouble').value.trim():'',code:type==='Packer'?$('packer-code').value.trim():'',cigarettes:type==='Packer'?$('packer-cigarettes').value:'',packCount:type==='Packer'?$('packer-pack-count').value:''};
  }
  function updateTargets(){const s=BRAND_SPECS[$('maker-brand').value];for(const [key,meta] of Object.entries(PHYSICAL))$(`target-${key}`).textContent=s?`LSL ${num(s[key][0])} · USL ${num(s[key][1])} ${meta.unit}`:'Pilih brand untuk melihat target'}
  function updateForm(type){const r=draft(type),a=assess(r),prefix=type==='Maker'?'maker':'packer',names=type==='Maker'?MAKER_VISUAL:PACKER_VISUAL;
    const status=$(`${prefix}-status`);status.textContent=a.status==='INVALID'?'PERIKSA INPUT':a.status==='PENDING'?'BELUM DINILAI':a.status==='BAD'?'BAD · REJECT':'GOOD · PASS';status.className=a.status==='BAD'?'status-bad':a.status==='GOOD'?'status-good':'status-pending';
    $(`${prefix}-reason`).textContent=a.issues.length?a.issues.slice(0,3).join(' · '):`Parameter terisi sesuai spesifikasi.${r.noFinding?' Tidak ada temuan lain.':''}`;
    $(`${prefix}-in`).textContent=`In-Spec ${pct(a.good,a.inspected)}`;$(`${prefix}-out`).textContent=`Out-Spec ${pct(a.inspected-a.good,a.inspected)}`;
    names.forEach((name,i)=>{const v=r.visual[name],el=$(`${prefix}-result-${i}`);el.textContent=v==null||!r.sample?'In-Spec — · Out-Spec —':`In-Spec ${pct(v,r.sample)} · Out-Spec ${pct(r.sample-v,r.sample)}`;el.style.color=v!=null&&v<r.sample?'#ff9cae':'#bdeed8';const inp=$(`${prefix}-${i}`);inp.max=String(r.sample||10000)});
  }
  function showView(id){
    if(['maker','packer'].includes(id)&&!canWrite())return;
    if(currentUser?.role==='GUEST_EXTERNAL'&&id!=='dashboard')return;
    if(id==='settings'&&currentUser?.role!=='ADMIN')return;
    document.querySelectorAll('.section').forEach(el=>el.classList.toggle('active',el.id===id));
    document.querySelectorAll('.nav-button').forEach(el=>{if(el.dataset.view===id)el.setAttribute('aria-current','page');else el.removeAttribute('aria-current')});
    const info={dashboard:['Ringkasan Produksi SKM','Dashboard harian, mingguan, dan bulanan untuk Maker dan Packaging dalam satu halaman.'],maker:['Maker Station · Rokok Batangan','Catat pemeriksaan physical dan jumlah batang baik per parameter visual.'],packer:['Packer Station · Packaging','Catat jumlah pack baik, lalu lihat status GOOD atau BAD otomatis.'],history:['Data Inspeksi SKM','Telusuri semua hasil inspeksi dari periode dan bagian SKM.'],settings:['Pengaturan Akun SKM','Kelola akses Admin, QC Inspector, dan Guest seperti dashboard SKT.']};
    $('view-title').textContent=info[id][0];$('view-description').textContent=info[id][1];
    if(id==='dashboard')renderDashboard();if(id==='history')renderHistory();if(id==='settings')loadUsers();
    window.scrollTo({top:0,behavior:'smooth'});
  }
  function tableMarkup(rows,includeActions){if(!rows.length)return '<div class="empty">Belum ada inspeksi pada filter yang dipilih.</div>';return `<div class="table-wrap"><table><thead><tr><th>Tanggal / Jam</th><th>Bagian</th><th>Brand / Mesin</th><th>QC / Shift</th><th>In / Out</th><th>Hasil</th><th>Temuan / Keterangan</th><th>Sumber</th>${includeActions?'<th>Aksi</th>':''}</tr></thead><tbody>${rows.map(r=>`<tr><td>${safe(displayDate(r.date))}<br><span class="muted">${safe(r.time)}</span></td><td>${r.type==='Maker'?'Rokok Batangan':'Packaging'}</td><td><b>${safe(r.brand)}</b><br>${safe(r.machine)}</td><td>${safe(r.qc)}<br><span class="muted">${safe(r.shift)}</span></td><td>${pct(r.result.good,r.result.inspected)} / ${pct(r.result.inspected-r.result.good,r.result.inspected)}</td><td><span class="tag ${r.result.status==='GOOD'?'good':'bad'}">${r.result.status}</span></td><td>${safe(r.result.issues.slice(0,2).join('; ')||r.trouble||r.notes||'Tidak ada temuan')} ${r.result.issues.length>2?`(+${r.result.issues.length-2} lainnya)`:''}</td><td><span class="tag ${r.source==='Contoh'?'demo':'local'}">${safe(r.source||'Tersimpan')}</span></td>${includeActions?`<td>${canDeleteRecord(r)?`<button type="button" class="delete" data-delete="${safe(r.id)}" aria-label="Hapus inspeksi">Hapus</button>`:'—'}</td>`:''}</tr>`).join('')}</tbody></table></div>`}
  function chartLine(points,{lo,hi,unit='',percent=false}={}){
    if(!points.length)return '<div class="empty" style="width:100%">Belum ada pengukuran untuk filter ini.</div>';
    const w=560,h=176,left=43,right=14,top=15,bottom=26,vals=points.map(p=>p.value),vmin=percent?0:Math.min(lo,...vals),vmax=percent?100:Math.max(hi,...vals),span=Math.max(1,(vmax-vmin)*.17),min=percent?0:vmin-span,max=percent?100:vmax+span;
    const x=i=>left+(w-left-right)*(points.length===1?.5:i/(points.length-1)),y=v=>top+(h-top-bottom)*(1-(v-min)/(max-min));
    const grid=Array.from({length:5},(_,i)=>{const v=max-(max-min)*i/4,yy=y(v);return `<line x1="${left}" y1="${yy}" x2="${w-right}" y2="${yy}" stroke="#473451" stroke-width="1"/><text x="${left-6}" y="${yy+3}" text-anchor="end" fill="#baa7cf" font-size="9">${percent?Math.round(v)+'%':num(v)}</text>`}).join('');
    const limits=percent?'':[lo,hi].map(v=>`<line x1="${left}" x2="${w-right}" y1="${y(v)}" y2="${y(v)}" stroke="#ffd075" stroke-dasharray="5 4" stroke-width="1.3"/>`).join('');
    const line=points.map((p,i)=>`${i?'L':'M'} ${x(i).toFixed(1)} ${y(p.value).toFixed(1)}`).join(' ');
    const marks=points.map((p,i)=>{const out=!percent&&(p.value<lo||p.value>hi),clr=out?'#ff738e':'#96a9ff';return `<circle cx="${x(i)}" cy="${y(p.value)}" r="${out?4.2:points.length>45?1.8:2.8}" fill="${clr}"><title>${safe(p.label)}: ${num(p.value)} ${unit}${out?' · Out-Spec':''}</title></circle>`}).join('');
    const ticks=[0,Math.floor((points.length-1)/2),points.length-1].filter((v,i,a)=>a.indexOf(v)===i).map(i=>`<text x="${x(i)}" y="${h-5}" text-anchor="middle" fill="#b8a5ca" font-size="9">${safe(points[i].label)}</text>`).join('');
    return `<svg viewBox="0 0 ${w} ${h}" preserveAspectRatio="none" role="img" aria-label="Grafik nilai aktual dan batas spesifikasi"><rect x="${left}" y="${top}" width="${w-left-right}" height="${h-top-bottom}" fill="#21182f"/>${grid}${limits}<path d="${line}" fill="none" stroke="#92a6fa" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"/>${marks}${ticks}</svg>`;
  }
  function trends(rows,bounds){const kind=$('period').value,slots=[];
    if(kind==='daily'){const ranges=[[6,12],[12,18],[18,24],[0,6]];ranges.forEach(([start,end])=>{const relevant=rows.filter(r=>{const hour=+r.time.slice(0,2);return hour>=start&&hour<end});slots.push({label:`${String(start).padStart(2,'0')}.00`,rows:relevant})})}
    else{let d=dateOf(bounds.start);while(dateKey(d)<=bounds.end){if(kind==='monthly'||(d.getDay()!==0&&d.getDay()!==6)){const day=dateKey(d);slots.push({label:kind==='weekly'?new Intl.DateTimeFormat('id-ID',{weekday:'short'}).format(d):String(d.getDate()),rows:rows.filter(r=>r.date===day)})}d.setDate(d.getDate()+1)}}
    const nonempty=slots.filter(s=>s.rows.length);$('trend-subtitle').textContent=kind==='daily'?'GOOD per jam sampling':kind==='weekly'?'GOOD per hari kerja':'GOOD per tanggal';$('trend-chart').innerHTML=chartLine(nonempty.map(s=>({label:s.label,value:100*s.rows.filter(r=>r.result.status==='GOOD').length/s.rows.length})),{percent:true});
    const delta=nonempty.length>1?100*(nonempty.at(-1).rows.filter(r=>r.result.status==='GOOD').length/nonempty.at(-1).rows.length-nonempty[0].rows.filter(r=>r.result.status==='GOOD').length/nonempty[0].rows.length):null;
    $('trend-change').textContent=delta==null?'Belum ada pembanding':`${delta>0?'+':''}${delta.toFixed(1)} poin vs awal periode`;$('trend-change').className=`compare ${delta>0?'positive':delta<0?'negative':''}`;
  }
  function renderPhysical(rows){const brand=$('physical-brand').value,machine=$('physical-machine').value,makers=rows.filter(r=>r.type==='Maker'&&r.brand===brand&&(machine==='ALL'||r.machine===machine)).slice().reverse();
    $('physical-charts').innerHTML=Object.entries(PHYSICAL).map(([key,meta])=>{const [lo,hi]=BRAND_SPECS[brand][key],measured=makers.filter(r=>r.physical?.[key]!=null&&Number.isFinite(Number(r.physical[key]))),avg=measured.length?measured.reduce((a,r)=>a+Number(r.physical[key]),0)/measured.length:null,points=measured.map(r=>({value:Number(r.physical[key]),label:`${r.date.slice(5)} ${r.time} · ${r.machine}`}));return `<article class="panel chart-panel"><div class="panel-title"><div><h3>${meta.label}</h3><p>LSL ${num(lo)} · USL ${num(hi)} ${meta.unit}</p></div><div style="text-align:right"><b>${avg==null?'—':num(avg)+' '+meta.unit}</b><div class="tiny muted">Rata-rata · ${measured.length} titik</div></div></div><div class="plot">${chartLine(points,{lo,hi,unit:meta.unit})}</div><div class="legend"><span>Aktual</span><span class="limit">Batas target</span><span class="outside">Out-Spec</span></div></article>`}).join('')}
  function renderDashboard(){const bounds=periodBounds(),rows=filtered(),good=rows.filter(r=>r.result.status==='GOOD').length,bad=rows.length-good,inspected=rows.reduce((a,r)=>a+r.result.inspected,0),passes=rows.reduce((a,r)=>a+r.result.good,0),maker=rows.filter(r=>r.type==='Maker').length,packer=rows.length-maker;
    $('period-caption').innerHTML=`<strong>${safe(bounds.caption)}</strong> · ${maker} inspeksi Rokok Batangan · ${packer} inspeksi Packaging${$('show-demo').checked?' · termasuk data contoh':''}`;
    for(const [type,prefix] of [['Maker','maker'],['Packer','packer']]){
      const station=rows.filter(r=>r.type===type),samples=station.reduce((sum,r)=>sum+r.result.inspected,0),passed=station.reduce((sum,r)=>sum+r.result.good,0);
      $(`${prefix}-score`).textContent=pct(passed,samples);
      $(`${prefix}-out-score`).textContent=`Out: ${pct(samples-passed,samples)}`;
      $(`${prefix}-summary-count`).textContent=`${num(station.length)} pemeriksaan · overall In-Spec`;
    }
    $('kpi-total').textContent=num(rows.length);$('kpi-total-sub').textContent=`${maker} Maker + ${packer} Packaging`;$('kpi-good').textContent=num(good);$('kpi-good-sub').textContent=`${pct(good,rows.length)} dari inspeksi`;$('kpi-bad').textContent=num(bad);$('kpi-bad-sub').textContent=bad?'Lihat warning untuk produksi':'Tidak ada temuan pada periode ini';$('kpi-rate').textContent=`${pct(passes,inspected)} / ${pct(inspected-passes,inspected)}`;$('kpi-rate-sub').textContent='Persentase parameter yang diisi';
    trends(rows,bounds);const counts={};rows.forEach(r=>r.result.issues.forEach(issue=>{const key=issue.split(':')[0].split(/ \d/)[0].slice(0,33);counts[key]=(counts[key]||0)+1}));const popular=Object.entries(counts).sort((a,b)=>b[1]-a[1]).slice(0,6),max=popular[0]?.[1]||1;
    $('issue-bars').innerHTML=popular.length?popular.map(([label,count])=>`<div class="bar-row"><span>${safe(label)}</span><span class="bar-track"><span class="bar-fill" style="display:block;width:${100*count/max}%"></span></span><b>${count}</b></div>`).join(''):'<div class="empty">Belum ada temuan pada periode ini.</div>';
    renderPhysical(rows);const warnings=rows.filter(r=>r.result.status==='BAD').slice(0,4);$('production-alerts').innerHTML=warnings.length?warnings.map(r=>`<div class="alert"><b>${safe(r.brand)} · ${safe(r.machine)} · ${r.type==='Maker'?'Rokok Batangan':'Packaging'} · ${safe(displayDate(r.date))} ${safe(r.time)}</b><br>${safe(r.result.issues.slice(0,3).join(' · '))}<br><span class="muted">Tindak lanjut: periksa setting mesin dan lakukan sampling ulang.</span></div>`).join(''):'<div class="alert ok">Tidak ada inspeksi BAD pada periode ini.</div>';
    $('recent-table').innerHTML=tableMarkup(rows.slice(0,8),false);
  }
  function historyRows(){return allRecords().filter(r=>(!$('history-date').value||r.date===$('history-date').value)&&($('history-type').value==='ALL'||r.type===$('history-type').value)&&($('history-brand').value==='ALL'||r.brand===$('history-brand').value)&&($('history-status').value==='ALL'||r.result.status===$('history-status').value))}
  function renderHistory(){const rows=historyRows();$('history-count').textContent=`${num(rows.length)} inspeksi ditemukan · menampilkan maksimal 100 terbaru`;$('history-table').innerHTML=tableMarkup(rows.slice(0,100),canWrite())}
  function exportCSV(){const rows=historyRows();if(!rows.length){showToast('Tidak ada data pada filter untuk diekspor.');return}const header=['Tanggal','Jam','Bagian','Nama QC','Shift','Brand','Mesin','Jumlah Sampel','In-Spec','Out-Spec','Status','Temuan','Trouble Point','Keterangan','Sumber'],q=v=>`"${String(v??'').replace(/"/g,'""')}"`,lines=[header,...rows.map(r=>[r.date,r.time,r.type==='Maker'?'Rokok Batangan':'Packaging',r.qc,r.shift,r.brand,r.machine,r.sample,pct(r.result.good,r.result.inspected),pct(r.result.inspected-r.result.good,r.result.inspected),r.result.status,r.result.issues.join('; '),r.trouble,r.notes,r.source||'Tersimpan'])];const blob=new Blob(['\uFEFF'+lines.map(line=>line.map(q).join(',')).join('\r\n')],{type:'text/csv;charset=utf-8'}),url=URL.createObjectURL(blob),a=document.createElement('a');a.href=url;a.download=`inspeksi-skm-${today()}.csv`;a.click();setTimeout(()=>URL.revokeObjectURL(url),1000)}
  function mapInspection(row){
    return {
      id:row.id,authorId:row.authorId,source:row.source||'Supabase',type:row.type,
      date:row.date,time:String(row.time).slice(0,5),qc:row.qc,
      shift:row.shift,brand:row.brand,machine:row.machine,sample:Number(row.sample),
      physical:row.physical||{},visual:row.visual||{},noFinding:Boolean(row.noFinding),
      trouble:row.trouble||'',notes:row.notes||'',code:row.code||'',
      cigarettes:row.cigarettes??'',packCount:row.packCount??''
    };
  }

  function toDatabase(r){
    return {
      type:r.type,date:r.date,time:r.time,shift:r.shift,brand:r.brand,machine:r.machine,
      sample:r.sample,physical:r.physical,visual:r.visual,noFinding:r.noFinding,
      trouble:r.trouble,notes:r.notes,code:r.code,
      cigarettes:r.cigarettes===''?'':Number(r.cigarettes),
      packCount:r.packCount===''?'':Number(r.packCount)
    };
  }

  function showAuth(message='',needsBootstrap=false){
    activeSession++;
    currentUser=null;managedUsers=[];manual=[];
    document.body.classList.remove('authenticated');
    $('app-root').classList.add('hidden');
    $('auth-screen').classList.remove('hidden');
    $('auth-message').textContent=message;
    $('login-password').value='';
    $('setup-toggle').classList.toggle('hidden',!needsBootstrap);
    if(!needsBootstrap)$('setup-form').classList.add('hidden');
  }

  async function loadRecords(){
    if(!currentUser)return;
    const sequence=++loadSequence,userId=currentUser.id;
    $('sync-status').textContent='Mengambil data SKM dari Supabase…';
    try{
      const data=await window.skmApiRequest('/api/inspections');
      if(sequence!==loadSequence||currentUser?.id!==userId)return;
      manual=(data.inspections||[]).map(mapInspection);
      renderDashboard();renderHistory();
      $('sync-status').textContent=`${num(manual.length)} inspeksi tersinkron · ${new Intl.DateTimeFormat('id-ID',{hour:'2-digit',minute:'2-digit'}).format(new Date())}`;
    }catch(error){
      if(sequence!==loadSequence||currentUser?.id!==userId)return;
      if(Number(error.status)===401){showAuth('Sesi berakhir. Silakan login kembali.');return}
      $('sync-status').textContent='Gagal memuat data. Klik Segarkan untuk mencoba lagi.';
      showToast(`Gagal membaca data: ${error.message||error}`);
    }
  }

  async function activateSession(user){
    if(!user){showAuth();return}
    currentUser=user;
    const roleLabel={ADMIN:'Admin',INSPECTOR:'QC Inspector',GUEST_INTERNAL:'Guest Internal',GUEST_EXTERNAL:'Guest External'}[user.role]||user.role;
    $('user-label').textContent=`${user.displayName} · ${roleLabel}`;
    for(const id of ['maker-qc','packer-qc']){$(id).value=user.displayName;$(id).readOnly=true}
    document.querySelectorAll('.tabs .nav-button[data-view="maker"],.tabs .nav-button[data-view="packer"]')
      .forEach(button=>button.classList.toggle('hidden',!canWrite()));
    $('history-nav').classList.toggle('hidden',user.role==='GUEST_EXTERNAL');
    $('settings-nav').classList.toggle('hidden',user.role!=='ADMIN');
    document.body.classList.add('authenticated');
    $('auth-screen').classList.add('hidden');
    $('app-root').classList.remove('hidden');
    showView('dashboard');
    await loadRecords();
  }

  async function initializeBackend(){
    try{
      if(typeof window.skmApiRequest!=='function')throw new Error('File skm-api.js belum dimuat.');
      const status=await window.skmApiRequest('/api/auth/status');
      if(status.user)await activateSession(status.user);
      else showAuth(status.needsBootstrap?'Belum ada akun. Klik Setup Admin Pertama.':undefined,Boolean(status.needsBootstrap));
    }catch(error){
      showAuth(`Tidak dapat menyiapkan login: ${error.message||error}`);
    }
  }

  async function saveInspection(type,form){
    if(!canWrite()){showToast('Akun ini tidak memiliki izin mengisi data.');return}
    const r=draft(type),assessment=assess(r);
    if(assessment.status==='INVALID'||assessment.status==='PENDING'){
      showToast(assessment.issues[0]);return;
    }
    const submit=form.querySelector('[type="submit"]');
    submit.disabled=true;submit.textContent='Menyimpan…';
    try{
      await window.skmApiRequest('/api/inspections',{method:'POST',body:toDatabase(r)});
      form.reset();
      const prefix=type==='Maker'?'maker':'packer';
      $(`${prefix}-date`).value=today();$(`${prefix}-sample`).value='10';
      $(`${prefix}-qc`).value=currentUser.displayName;
      if(type==='Maker')updateTargets();updateForm(type);
      showToast(`Inspeksi ${type==='Maker'?'Rokok Batangan':'Packaging'} ${assessment.status} tersimpan di Supabase.`);
      await loadRecords();
    }catch(error){showToast(`Gagal menyimpan inspeksi: ${error.message||error}`)}
    finally{submit.disabled=false;submit.textContent=`Simpan Inspeksi ${type==='Maker'?'Rokok Batangan':'Packaging'}`}
  }

  async function removeInspection(id){
    const record=manual.find(r=>r.id===id);
    if(!record||!canDeleteRecord(record))return;
    if(!confirm('Hapus inspeksi ini dari Supabase untuk seluruh tim SKM?'))return;
    try{
      await window.skmApiRequest(`/api/inspections/${id}`,{method:'DELETE'});
      showToast('Inspeksi dihapus dari Supabase.');
      await loadRecords();
    }catch(error){showToast(`Gagal menghapus data: ${error.message||error}`)}
  }

  function renderUsers(){
    if(!managedUsers.length){$('users-list').innerHTML='<div class="empty">Belum ada akun.</div>';return}
    const labels={ADMIN:'Admin',INSPECTOR:'QC Inspector',GUEST_INTERNAL:'Guest Internal',GUEST_EXTERNAL:'Guest External'};
    $('users-list').innerHTML=managedUsers.map(user=>`<div class="alert ${user.isActive?'ok':''}"><div style="display:flex;justify-content:space-between;align-items:center;gap:12px"><div><b>${safe(user.displayName)}</b><br><span class="muted">@${safe(user.username)} · ${safe(labels[user.role]||user.role)}</span></div><button type="button" class="secondary" data-user-toggle="${safe(user.id)}" data-active="${user.isActive}">${user.isActive?'Nonaktifkan':'Aktifkan'}</button></div></div>`).join('');
  }

  async function loadUsers(){
    if(currentUser?.role!=='ADMIN')return;
    $('users-list').innerHTML='<div class="empty">Memuat akun…</div>';
    try{const data=await window.skmApiRequest('/api/users');managedUsers=data.users||[];renderUsers()}
    catch(error){$('users-list').innerHTML=`<div class="alert">${safe(error.message||error)}</div>`}
  }

  async function createUser(){
    const button=$('user-submit');button.disabled=true;button.textContent='Membuat…';
    try{
      await window.skmApiRequest('/api/users',{method:'POST',body:{displayName:$('user-name').value.trim(),username:$('user-username').value.trim(),password:$('user-password').value,role:$('user-role').value}});
      $('user-form').reset();showToast('Akun pengguna berhasil dibuat.');await loadUsers();
    }catch(error){showToast(`Gagal membuat akun: ${error.message||error}`)}
    finally{button.disabled=false;button.textContent='Buat Akun'}
  }

  async function toggleUser(id,isActive){
    try{await window.skmApiRequest(`/api/users/${id}`,{method:'PATCH',body:{isActive:!isActive}});showToast(`Akun berhasil ${isActive?'dinonaktifkan':'diaktifkan'}.`);await loadUsers()}
    catch(error){showToast(`Gagal mengubah akun: ${error.message||error}`)}
  }

  function setup(){
    $('auth-ati-logo').src=$('ati-logo').src;
    const now=today();
    $('period-date').value=now;$('period-month').value=now.slice(0,7);
    $('maker-date').value=now;$('packer-date').value=now;
    const hours=Array.from({length:24},(_,i)=>`${String((i+6)%24).padStart(2,'0')}:00`);
    ['maker-time','packer-time'].forEach(id=>$(id).innerHTML='<option value="">Pilih jam</option>'+hours.map(h=>`<option>${h}</option>`).join(''));
    $('physical-fields').innerHTML=Object.entries(PHYSICAL).map(([key,m])=>`<div class="field"><label for="maker-${key}">${m.label} (${m.unit})</label><input id="maker-${key}" type="number" step="${m.step}" min="0" placeholder="Nilai terukur"><span class="target" id="target-${key}">Pilih brand untuk melihat target</span></div>`).join('');
    buildVisual('maker-visuals',MAKER_VISUAL,'maker');buildVisual('packer-visuals',PACKER_VISUAL,'packer');
    document.querySelectorAll('[data-view]').forEach(button=>button.addEventListener('click',()=>showView(button.dataset.view)));
    $('sidebar-toggle').addEventListener('click',()=>{const hidden=document.body.classList.toggle('nav-collapsed');$('sidebar-toggle').setAttribute('aria-expanded',String(!hidden))});
    ['period','period-date','period-month','filter-brand','filter-station','show-demo','physical-brand','physical-machine']
      .forEach(id=>$(id).addEventListener('change',()=>{
        if(id==='period'){
          $('day-wrap').classList.toggle('hidden',$('period').value==='monthly');
          $('month-wrap').classList.toggle('hidden',$('period').value!=='monthly');
        }
        if(id==='filter-brand'&&BRAND_SPECS[$('filter-brand').value])$('physical-brand').value=$('filter-brand').value;
        renderDashboard();if($('history').classList.contains('active'))renderHistory();
      }));
    ['history-date','history-type','history-brand','history-status'].forEach(id=>$(id).addEventListener('change',renderHistory));
    $('history-clear').addEventListener('click',()=>{
      ['history-date','history-type','history-brand','history-status'].forEach(id=>$(id).value=id==='history-date'?'':'ALL');renderHistory();
    });
    $('export-csv').addEventListener('click',exportCSV);
    $('history-table').addEventListener('click',e=>{
      const button=e.target.closest('[data-delete]');if(button)removeInspection(button.dataset.delete);
    });
    for(const type of ['Maker','Packer']){
      const prefix=type==='Maker'?'maker':'packer',form=$(`${prefix}-form`);
      form.addEventListener('input',()=>{if(type==='Maker')updateTargets();updateForm(type)});
      form.addEventListener('change',()=>{if(type==='Maker')updateTargets();updateForm(type)});
      form.addEventListener('reset',()=>setTimeout(()=>{
        $(`${prefix}-date`).value=today();$(`${prefix}-sample`).value='10';
        if(currentUser)$(`${prefix}-qc`).value=currentUser.displayName;
        if(type==='Maker')updateTargets();updateForm(type);
      },0));
      form.addEventListener('submit',event=>{event.preventDefault();saveInspection(type,form)});
    }
    $('login-form').addEventListener('submit',async event=>{
      event.preventDefault();
      const button=$('login-button');button.disabled=true;$('auth-message').textContent='Sedang masuk…';
      try{
        const data=await window.skmApiRequest('/api/auth/login',{method:'POST',body:{username:$('login-username').value.trim(),password:$('login-password').value}});
        await activateSession(data.user);
      }catch(error){$('auth-message').textContent=`Login gagal: ${error.message||error}`}
      finally{button.disabled=false}
    });
    $('login-password-toggle').addEventListener('click',()=>{
      const input=$('login-password'),button=$('login-password-toggle'),show=input.type==='password';
      input.type=show?'text':'password';
      button.setAttribute('aria-pressed',String(show));
      button.setAttribute('aria-label',show?'Sembunyikan password':'Tampilkan password');
      input.focus();
    });
    $('setup-toggle').addEventListener('click',()=>$('setup-form').classList.toggle('hidden'));
    $('setup-form').addEventListener('submit',async event=>{
      event.preventDefault();const button=$('setup-button');button.disabled=true;button.textContent='Membuat Admin…';$('auth-message').textContent='Menyiapkan Admin pertama…';
      try{
        const data=await window.skmApiRequest('/api/auth/bootstrap',{method:'POST',body:{displayName:$('setup-name').value.trim(),username:$('setup-username').value.trim(),password:$('setup-password').value}});
        $('setup-form').reset();await activateSession(data.user);showToast('Admin pertama berhasil dibuat.');
      }catch(error){$('auth-message').textContent=`Setup gagal: ${error.message||error}`}
      finally{button.disabled=false;button.textContent='Buat Admin Pertama'}
    });
    $('logout-button').addEventListener('click',async()=>{
      try{await window.skmApiRequest('/api/auth/logout',{method:'POST'});showAuth('Kamu sudah keluar. Silakan login kembali.')}
      catch(error){showToast(`Gagal keluar: ${error.message||error}`)}
    });
    $('user-form').addEventListener('submit',event=>{event.preventDefault();createUser()});
    $('users-refresh').addEventListener('click',loadUsers);
    $('users-list').addEventListener('click',event=>{
      const button=event.target.closest('[data-user-toggle]');if(button)toggleUser(button.dataset.userToggle,button.dataset.active==='true');
    });
    $('refresh-data').addEventListener('click',loadRecords);
    document.addEventListener('visibilitychange',()=>{if(!document.hidden&&currentUser)loadRecords()});
    setInterval(()=>{if(!document.hidden&&currentUser)loadRecords()},60000);
    updateTargets();updateForm('Maker');updateForm('Packer');renderDashboard();renderHistory();
  }
  setup();
  initializeBackend();
