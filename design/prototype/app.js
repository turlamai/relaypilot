(() => {
  'use strict';
  const surface=document.body.dataset.surface || 'desktop';
  const root = document.getElementById('root');
  const modal = document.getElementById('modal');
  const toast = document.getElementById('toast');
  const paths = {
    grid:'M3 3h7v7H3z M14 3h7v7h-7z M3 14h7v7H3z M14 14h7v7h-7z',
    route:'M5 3v12a4 4 0 0 0 4 4h10 M15 15l4 4-4 4 M5 7h10a4 4 0 0 1 4 4v1',
    file:'M14 2H5v20h14V7z M14 2v6h5 M8 12h8 M8 16h6',
    settings:'M4 7h16 M4 17h16 M8 4v6 M16 14v6',
    arrow:'M5 12h14 M14 7l5 5-5 5',
    check:'M5 12l4 4L19 6',
    close:'M6 6l12 12 M18 6L6 18',
    power:'M12 2v10 M5 5a9 9 0 1 0 14 0',
    shield:'M12 3l8 3v6c0 5-8 9-8 9S4 17 4 12V6z M8 12l3 3 5-6',
    info:'M12 11v6 M12 7h.01 M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0',
    plus:'M12 5v14 M5 12h14',
    copy:'M9 9h12v12H9z M15 5V3H3v12h2',
    warning:'M12 3L2 21h20z M12 9v5 M12 17h.01',
    back:'M19 12H5 M10 7l-5 5 5 5',
    search:'M20 20l-5-5 M17 10a7 7 0 1 1-14 0 7 7 0 0 1 14 0',
    edit:'M4 16L16 4l4 4L8 20H4z M14 6l4 4',
    moon:'M20 15A9 9 0 0 1 9 3a9 9 0 1 0 11 12'
  };
  const icon = (name) => `<svg class="od-icon" viewBox="0 0 24 24" aria-hidden="true"><path d="${paths[name] || paths.info}"/></svg>`;
  const esc = value => String(value).replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  const rules = () => [
    {type:'DOMAIN-SUFFIX',value:'lab.internal',policy:'DIRECT'},
    {type:'DOMAIN-SUFFIX',value:'github.com',policy:'policy-main'},
    {type:'FINAL',value:'',policy:'policy-main'}
  ];
  const state = {
    view:document.body.dataset.page || 'connect', session:'idle', active:'home', selected:'home', target:'nas.lab.internal', input:'nas.lab.internal', inspecting:false,
    profiles:[
      {id:'home',name:'home-lab.yaml',status:'valid',description:'家庭实验室',rules:rules()},
      {id:'office',name:'office-inline.yaml',status:'pending',description:'办公环境',rules:[{type:'DOMAIN-SUFFIX',value:'office.internal',policy:'DIRECT'}]},
      {id:'legacy',name:'legacy-full.conf',status:'invalid',description:'完整配置尚未转换',rules:[]}
    ],
    events:[{time:'示例',text:'家庭实验室配置已通过示例规则校验。'}],
    query:'', filter:'all', expected:{'nas.lab.internal':'DIRECT','github.com':'policy-main'}, inspectionToken:0, commandQuery:'', revision:1, theme:'system', redact:true, undo:null, importResult:null, connectionToken:0
  };
  try { const saved = JSON.parse(localStorage.getItem('relaypilot-preferences-v2') || '{}'); if (['system','light','dark'].includes(saved.theme)) state.theme=saved.theme; if(typeof saved.redact==='boolean') state.redact=saved.redact; } catch (_) { /* In-memory preferences remain available. */ }
  const names = {connect:'运行概览',trace:'路由检查',profiles:'配置库',settings:'设置'};
  const $ = (selector, parent=document) => parent.querySelector(selector);
  const active = () => state.profiles.find(p=>p.id===state.active);
  const chosen = () => state.profiles.find(p=>p.id===state.selected) || active();
  const running = () => state.session==='running';
  const busy = () => state.session==='starting';
  function setTheme() {
    const dark = state.theme==='dark' || (state.theme==='system' && window.matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.dataset.theme=dark?'dark':'light';
  }
  function storePreferences() { try { localStorage.setItem('relaypilot-preferences-v2',JSON.stringify({theme:state.theme,redact:state.redact})); } catch (_) { /* Preferences remain active for this session. */ } }
  setTheme();
  window.matchMedia('(prefers-color-scheme: dark)').addEventListener('change',setTheme);
  function badge(text,type='') { return `<span class="badge ${type}">${icon(type==='ok'?'check':type==='warn'||type==='error'?'warning':'info')}${esc(text)}</span>`; }
  function event(text) { state.events.unshift({time:new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',hour12:false}),text}); state.events=state.events.slice(0,8); }
  let notifyTimer;
  function notify(message,undo=false) {
    clearTimeout(notifyTimer);
    toast.innerHTML=`<span>${esc(message)}</span>${undo?'<button type="button" data-action="undo">撤销</button>':''}<button type="button" data-action="dismiss" aria-label="关闭通知">关闭</button>`;
    toast.hidden=false;
    if(!undo) notifyTimer=setTimeout(()=>{toast.hidden=true;},5500);
  }
  function snapshot() { return {profiles:JSON.parse(JSON.stringify(state.profiles)),active:state.active,selected:state.selected,revision:state.revision}; }
  function go(view,focus=true) { state.view=view; render(); if(focus) { const heading=$('h1',root); if(heading)heading.focus({preventScroll:true}); } }
  const policyName = policy => ({DIRECT:'直接连接',REJECT:'拒绝连接','policy-main':'通过策略组'}[policy] || '未设置');
  const sessionName = () => running()?'运行中':busy()?'正在校验':'未运行';
  const keyboard = /Mac|iPhone|iPad/.test(navigator.platform)?'⌘ K':'Ctrl K';
  const matchText = (query,text) => text.toLowerCase().includes(query.trim().toLowerCase());
  const filteredProfiles = () => state.profiles.filter(p=>(state.filter==='all'||p.status===state.filter)&&matchText(state.query,p.name+' '+p.description));
  function openProfile(id) { state.query='';state.filter='all';state.selected=id;go('profiles'); }
  function shell(content) {
    const pending=state.profiles.filter(p=>p.status!=='valid').length;
    const nav = Object.entries(names).map(([id,name])=>`<button type="button" class="nav-button ${state.view===id?'active':''}" data-view="${id}" ${state.view===id?'aria-current="page"':''}>${icon({connect:'grid',trace:'route',profiles:'file',settings:'settings'}[id])}<span>${name}</span>${id==='profiles'?`<span class="nav-meta">${pending?pending+' 待处理':state.profiles.length}</span>`:''}</button>`).join('');
    return `<div class="app"><aside class="sidebar"><div class="wordmark"><span class="mark">${icon('route')}</span>RelayPilot</div><nav class="nav" aria-label="主导航">${nav}</nav><div class="sidebar-bottom"><div class="local-note">${icon('shield')}<span>本地工作空间<br>变更前预览，应用后可撤销</span></div></div></aside><main class="main"><header class="topbar"><div class="breadcrumb"><span>工作空间</span><span aria-hidden="true">/</span><strong>${names[state.view]}</strong></div><div class="od-cluster">${state.undo?'<button type="button" class="btn subtle" data-action="undo">撤销上次变更</button>':''}<button type="button" class="btn command-trigger" data-action="commands" aria-label="快速查找页面、配置与目标">${icon('search')}<span>快速查找</span><kbd>${keyboard}</kbd></button></div></header><div class="prototype-notice">${icon('info')}<span>交互原型 · 所有运行状态与路由结果均为本地模拟，不接管真实网络</span></div><div class="content">${content}</div><footer class="footer"><span>${sessionName()} · ${esc(active().name)}</span><span>规则版本 r${state.revision} · 修改仅在本次会话有效</span></footer></main></div>`;
  }
  function heading(title,description,action='') { return `<div class="page-heading"><div><h1 tabindex="-1">${title}</h1><p>${description}</p></div>${action}</div>`; }
  function getRoute(target=state.target,profile=active()) {
    const index=profile.rules.findIndex(r=>r.type==='FINAL'||(r.type==='DOMAIN'&&target===r.value)||(r.type==='DOMAIN-SUFFIX'&&(target===r.value||target.endsWith('.'+r.value))));
    const rule=index<0?null:profile.rules[index];
    const direct=rule?.policy==='DIRECT';
    const reject=rule?.policy==='REJECT';
    return {rule,index,direct,reject,matchedKind:rule?.type||null,exit:!rule?'没有匹配规则':direct?'直接连接':reject?'拒绝连接':'proxy/lab-a',policy:rule?.policy||'无',source:rule?`${rule.type}${rule.value?', '+rule.value:''}, ${rule.policy}`:''};
  }
  function overview() {
    const p=active();
    const fallback=p.rules.find(r=>r.type==='FINAL');
    const fallbackName=fallback?policyName(fallback.policy):'未设置';
    const unresolved=state.profiles.filter(item=>item.status!=='valid');
    const mismatches=Object.entries(state.expected).filter(([target,expected])=>getRoute(target).policy!==expected);
    const issueCount=unresolved.length+mismatches.length;
    const label=running()?'运行中':busy()?'正在校验配置':'未运行';
    const sub=running()?'当前配置已载入，规则检查随时可用。':busy()?'正在检查规则格式与默认路由。':'当前配置已就绪，可启动会话或直接检查路由。';
    return heading('运行概览','当前状态、配置与需要处理的事项。')+`
      <section class="session" aria-label="会话状态"><div class="session-top"><div class="session-state"><span class="status-emblem ${running()?'running':''}">${icon(running()?'check':'power')}</span><div><div class="session-title" role="status">${label}</div><p class="session-sub">${sub}</p></div></div><button type="button" class="btn ${running()?'danger':'primary'} large" data-action="session" ${busy()?'disabled':''}>${icon('power')}${running()?'停止':busy()?'正在启动…':'启动'}</button></div>${busy()?'<div class="progress" aria-label="正在校验配置"><span></span></div>':''}<dl class="fact-grid"><div><dt>当前配置</dt><dd>${esc(p.name)}</dd><button type="button" class="action-link" data-action="choose-profile">管理配置</button></div><div><dt>默认路由</dt><dd>${esc(fallbackName)}</dd><dd class="muted">${esc(fallback?.policy||'缺少 FINAL 规则')}</dd></div><div><dt>配置状态</dt><dd>${p.rules.length} 条规则</dd><dd class="muted">${p.status==='valid'?'校验通过':'需要校验'}</dd></div></dl></section>
      <section class="section-block"><div class="section-head"><h2>待处理</h2>${badge(issueCount?issueCount+' 项':'已处理完毕',issueCount?'warn':'ok')}</div>${issueCount?`<div class="list">${unresolved.map(item=>`<button type="button" class="list-row issue-row" data-open-profile="${esc(item.id)}"><span class="issue-symbol">${icon(item.status==='pending'?'info':'warning')}</span><span class="od-field od-fill"><strong>${esc(item.name)}</strong><span class="hint">${item.id==='legacy'?'完整配置尚未转换，请查看支持范围。':item.status==='pending'?'尚未校验，检查后才能使用。':esc(item.errors?.[0]||'配置不完整，请修正规则后重新校验。')}</span></span><span class="row-action">${item.status==='pending'?'去校验':'去处理'} ${icon('arrow')}</span></button>`).join('')}${mismatches.map(([target,expected])=>`<button type="button" class="list-row issue-row" data-target="${esc(target)}"><span class="issue-symbol">${icon('route')}</span><span class="od-field od-fill"><strong class="mono">${esc(target)}</strong><span class="hint">预期${policyName(expected)}，当前${policyName(getRoute(target).policy)}。</span></span><span class="row-action">查看差异 ${icon('arrow')}</span></button>`).join('')}</div>`:`<div class="clear-state">${icon('check')}<div class="od-field"><strong>当前没有待处理事项</strong><span>所有配置已校验，已设置的路由预期均符合。</span></div></div>`}</section>
      <div class="split section-block"><section><div class="section-head"><h2>已保存目标</h2><button type="button" class="action-link" data-view="trace">检查其他目标</button></div><div class="list">${['nas.lab.internal','github.com'].map(target=>{const route=getRoute(target);const expected=state.expected[target];const mismatch=expected&&route.policy!==expected;return `<button type="button" class="list-row" data-target="${target}"><span class="od-field od-fill"><strong class="mono">${target}</strong><span class="hint">${esc(route.exit)} · ${mismatch?'与预期不同':expected?'符合预期':'未设置预期'}</span></span>${icon('arrow')}</button>`;}).join('')}</div></section><section><div class="section-head"><h2>操作记录</h2><span class="small muted">最近优先</span></div>${state.events.map(e=>`<div class="event-row"><time>${esc(e.time)}</time><p>${esc(e.text)}</p></div>`).join('')}</section></div>`;
  }
  function inspector() {
    const r=getRoute();
    const expected=state.expected[state.target]||'';
    const mismatch=expected&&r.policy!==expected;
    const prior=r.index>0?`前 ${r.index} 条规则未匹配，第 ${r.index+1} 条命中后停止匹配。`:'第 1 条规则命中后停止匹配，后续规则不再执行。';
    const cause=!r.rule?'当前配置没有覆盖此目标的规则。':r.rule.type==='FINAL'?'目标未命中前面的规则，最终采用兜底策略。':`第 ${r.index+1} 条${r.rule.type==='DOMAIN'?'精确域名':'域名后缀'}规则优先命中，结果由这条规则决定。`;
    const step=(num,title,body,source='')=>`<div class="trace-step"><span class="step-num">${num}</span><div><h3>${title}</h3><p>${body}</p>${source?`<details><summary>查看规则来源</summary><code class="source-code">${esc(active().name)} · rules[${r.index}]\n${esc(source)}</code></details>`:''}</div></div>`;
    return heading('路由检查','对照预期与计算结果，定位决定路由的那条规则。')+`
      <div class="search-form"><div class="field"><label for="target">目标域名</label><input id="target" type="text" inputmode="url" autocomplete="off" spellcheck="false" value="${esc(state.input)}" aria-describedby="target-error" placeholder="例如 nas.lab.internal"></div><button type="button" class="btn primary" data-action="inspect" ${state.inspecting?'disabled':''}>${icon('search')}${state.inspecting?'正在检查…':'检查路由'}</button></div><p id="target-error" class="field-error" role="alert" hidden></p><div class="examples"><span>已保存目标</span><button type="button" class="action-link" data-target="nas.lab.internal">nas.lab.internal</button><button type="button" class="action-link" data-target="github.com">github.com</button></div>
      ${state.inspecting?'<div class="note section-block" role="status">正在按顺序匹配规则…</div>':`<section aria-label="路由检查结果"><div class="result-heading"><h2 class="mono">${esc(state.target)}</h2>${badge(expected?(mismatch?'与预期不同':'符合预期'):'未设置预期',expected?(mismatch?'warn':'ok'):'')}</div><div class="comparison"><div class="expectation"><label for="expected-policy">你的预期</label><select id="expected-policy"><option value="">暂不设定</option>${['DIRECT','policy-main','REJECT'].map(v=>`<option value="${v}" ${expected===v?'selected':''}>${policyName(v)}</option>`).join('')}</select><p>预期只作对照，不改变规则。</p></div><div class="actual-result"><span class="comparison-label">计算结果</span><strong>${policyName(r.policy)}</strong><span class="mono">${esc(r.exit)}</span></div></div><div class="route-explanation ${mismatch?'attention':''}"><div class="od-field od-fill"><strong>${mismatch?'差异来自这里':r.rule?'决定结果的规则':'需要补充路由'}</strong><span>${cause}</span><code>${esc(r.source||'无匹配规则')}</code></div><button type="button" class="btn ${mismatch?'primary':''}" data-action="edit-rule">${icon('edit')}${mismatch?'按预期修正':'修改路由'}</button></div><div class="section-head section-block"><h2>决策过程</h2><span class="small muted">首条命中即停止</span></div><div class="trace-list">${step('01','载入当前配置',`${esc(active().name)} · ${active().rules.length} 条规则 · 版本 r${state.revision}`)}${step('02',r.rule?`命中${r.rule.type==='FINAL'?'兜底':'目标'}规则`:'没有匹配规则',r.rule?prior:'请添加目标规则或兜底规则后重试。',r.source)}${r.rule?step('03',r.direct?'直接连接':r.reject?'拒绝连接':'选择策略出口',r.direct?'最终策略 DIRECT，不再解析代理策略组。':r.reject?'最终策略 REJECT，不再选择出口。':'policy-main → proxy/lab-a。静态出口，不包含健康检测结果。'):''}</div><details class="technical"><summary>检查记录与技术详情</summary><dl><dt>trace_id</dt><dd>${esc(traceId())}</dd><dt>配置版本</dt><dd>demo-revision-${state.revision}</dd><dt>执行方式</dt><dd>本地规则模拟 · 无引擎调用</dd><dt>adapter / digest</dt><dd>未生成引擎 artifact，无真实版本与摘要</dd></dl><button type="button" class="btn" data-action="copy-trace">${icon('copy')}复制检查记录</button></details></section>`}`;
  }
  function traceId() { let hash=0; for(const c of state.target)hash=((hash<<5)-hash+c.charCodeAt(0))|0; return `demo-${Math.abs(hash).toString(16)}-r${state.revision}`; }
  function profileResults() {
    const items=filteredProfiles();
    const p=items.find(item=>item.id===state.selected);
    let detail=`<div class="selection-placeholder"><h2>${items.length?'选择一份配置':'没有匹配的配置'}</h2><p>${items.length?'点击列表查看规则、校验状态与可用操作。':'试试其他关键词，或清除筛选查看全部配置。'}</p><button type="button" class="btn" data-action="clear-filters">清除筛选</button></div>`;
    if(p){
      const status={valid:['校验通过','ok'],pending:['待校验','warn'],invalid:['需要处理','error']}[p.status];
      detail=`<section class="profile-detail" aria-label="配置详情"><div class="section-head"><h2>${esc(p.name)}</h2>${badge(status[0],status[1])}</div><p class="muted small">${esc(p.description)}${p.id===state.active?' · 当前使用':''}</p>${p.id==='legacy'?`<div class="note warn section-block">${icon('warning')}<div class="od-field"><strong>需要先转换完整配置</strong><span>通过导入预览确认支持范围与排除内容，再创建新配置。</span></div></div><div class="od-cluster section-block"><button type="button" class="btn" data-action="import">查看导入范围</button><button type="button" class="btn danger" data-action="delete-profile">删除配置</button></div>`:`${p.errors?.length?`<div class="note error section-block" role="status">${icon('warning')}<div><strong>校验未通过</strong><ul class="report-list">${p.errors.map(e=>`<li>${esc(e)}</li>`).join('')}</ul></div></div>`:''}<div class="section-head section-block"><h3>路由规则</h3><span class="small muted">${p.rules.length} 条 · 按顺序匹配</span></div>${p.rules.length?p.rules.map((rule,i)=>`<div class="rule-row"><span class="index">${String(i+1).padStart(2,'0')}</span><span class="od-field"><span class="rule-target">${esc(rule.value||'其余所有目标')}</span><span class="small muted">${esc(rule.type)}</span></span><span class="small">${esc(rule.policy)}</span></div>`).join(''):'<p class="empty">尚无路由规则，请添加后校验。</p>'}<div class="od-cluster section-block">${p.status!=='valid'?'<button type="button" class="btn primary" data-action="validate-profile">校验配置</button>':p.id===state.active?'<button type="button" class="btn" data-view="trace">检查当前路由</button>':`<button type="button" class="btn primary" data-action="use-profile" ${busy()?'disabled':''}>使用此配置</button>`}<button type="button" class="btn" data-action="edit-profile">编辑规则</button>${p.id!==state.active?'<button type="button" class="btn danger" data-action="delete-profile">删除配置</button>':''}</div>`}</section>`;
    }
    return `<p class="results-count" role="status">显示 ${items.length} / ${state.profiles.length} 份配置</p><div class="profile-layout"><div class="profile-list" aria-label="配置列表">${items.length?items.map(item=>`<button type="button" class="profile-button ${item.id===state.selected?'selected':''}" data-profile="${esc(item.id)}" aria-pressed="${item.id===state.selected}">${icon('file')}<span class="od-field od-fill"><strong>${esc(item.name)}</strong><span class="small muted">${esc(item.description)}</span><span>${item.id===state.active?badge('当前使用','ok'):badge(item.status==='valid'?'校验通过':item.status==='pending'?'待校验':'需要处理',item.status==='valid'?'':item.status==='pending'?'warn':'error')}</span></span></button>`).join(''):'<p class="empty">没有找到配置。</p>'}</div>${detail}</div>`;
  }
  function library() {
    return heading('配置库','查找、校验与切换配置。查看详情不会切换当前配置。',`<button type="button" class="btn primary" data-action="import">${icon('plus')}导入配置</button>`)+`<div class="library-toolbar"><div class="field"><label for="profile-search">搜索配置</label><input type="search" id="profile-search" autocomplete="off" placeholder="搜索名称或描述" value="${esc(state.query)}"></div><div class="field"><label for="profile-filter">校验状态</label><select id="profile-filter">${[['all','全部状态'],['valid','校验通过'],['pending','待校验'],['invalid','需要处理']].map(([value,title])=>`<option value="${value}" ${state.filter===value?'selected':''}>${title}</option>`).join('')}</select></div></div><div id="profile-results">${profileResults()}</div>`;
  }
  function settings() {
    return heading('设置','外观、隐私与变更保护。')+`
      <section class="settings-group"><h2>外观</h2><div class="settings-row"><div class="od-field"><label for="theme"><strong>主题</strong></label><span>为亮色与暗色分别提供清晰的文字和状态。</span></div><select id="theme">${[['system','跟随系统'],['light','浅色'],['dark','深色']].map(([v,n])=>`<option value="${v}" ${state.theme===v?'selected':''}>${n}</option>`).join('')}</select></div></section>
      <section class="settings-group"><h2>隐私与诊断</h2><div class="settings-row"><div class="od-field od-fill"><strong id="redact-label">导出时隐藏目标地址</strong><span>诊断记录会保留规则类型与路由结果。</span></div><button type="button" class="switch" role="switch" aria-checked="${state.redact}" aria-labelledby="redact-label" data-action="redact"><span>${state.redact?'已开启':'已关闭'}</span>${icon(state.redact?'check':'close')}</button></div><div class="settings-row"><div class="od-field od-fill"><strong>导出诊断记录</strong><span>下载当前目标的路由检查记录。</span></div><button type="button" class="btn" data-action="export">导出记录</button></div></section>
      <section class="settings-group"><h2>操作效率</h2><div class="settings-row"><div class="od-field"><strong>快速查找</strong><span>查找页面、配置或已保存目标。</span></div><button type="button" class="btn" data-action="commands">${icon('search')}快速查找 <kbd>${keyboard}</kbd></button></div><div class="settings-row"><div class="od-field"><strong>键盘操作</strong><span>非输入状态按 / 聚焦搜索；查找中用 ↑ ↓ 选择，Enter 打开，Esc 关闭。</span></div></div></section><section class="settings-group"><h2>变更保护</h2><div class="settings-row"><div class="od-field"><strong>应用前预览</strong><span>规则修改必须先展示变更和影响，再由你确认。</span></div>${badge('始终开启','ok')}</div><div class="settings-row"><div class="od-field"><strong>AI 辅助</strong><span>当前原型未接入 AI 服务，不会上传配置。</span></div>${badge('未接入')}</div></section><div class="note">${icon('info')}<span>外观与脱敏偏好会在浏览器允许时保存在本地。配置、规则修改和会话记录仅在本次打开期间有效。</span></div>`;
  }
  function render() { root.innerHTML=shell(({connect:overview,trace:inspector,profiles:library,settings})[state.view]()); }
  let modalReturn=null;
  function openDialog(title,description,body) {
    if(!modal.open)modalReturn=document.activeElement;
    modal.innerHTML=`<div class="dialog-header"><div><h2 id="dialog-title">${title}</h2><p>${description}</p></div><button type="button" class="btn subtle close-button" data-action="close-modal" aria-label="关闭对话框">${icon('close')}</button></div><div class="dialog-body">${body}</div>`;
    if(!modal.open)modal.showModal();
    const first=$('input:not([type=checkbox]),textarea,select',modal)||$('.dialog-actions [data-action="close-modal"]',modal)||$('button',modal); if(first)first.focus();
  }
  function closeDialog() { if(modal.open)modal.close(); }
  modal.addEventListener('close',()=>{ const fallback=$(`[data-view="${state.view}"]`,root); (modalReturn?.isConnected?modalReturn:fallback)?.focus(); });
  const actions=(primary,label,disabled=false)=>`<div class="dialog-actions"><button type="button" class="btn" data-action="close-modal">取消</button><button type="button" class="btn primary" data-action="${primary}" ${disabled?'disabled':''}>${label}</button></div>`;
  function confirmSession() {
    const stop=running();
    openDialog(stop?'停止当前会话？':'启动当前会话？',stop?'规则和配置保持不变，可随时重新启动。':'先检查规则与默认路由，通过后启动。',`<div class="field"><span class="small muted">当前配置</span><strong class="mono">${esc(active().name)}</strong></div>${actions(stop?'stop-session':'start-session',stop?'停止':'确认启动')}`);
  }
  let patch=null;
  function editRule() {
    const r=getRoute();
    const proposed=state.expected[state.target]||r.policy;
    openDialog('修改这条路由','只为当前目标添加一条优先规则，其他规则保持原顺序。',`<div class="field"><label>目标域名</label><code class="source-code">${esc(state.target)}</code></div><div class="field"><label for="new-policy">新的处理方式</label><select id="new-policy"><option value="DIRECT" ${proposed==='DIRECT'?'selected':''}>直接连接 · DIRECT</option><option value="policy-main" ${proposed==='policy-main'?'selected':''}>通过策略组 · policy-main</option><option value="REJECT" ${proposed==='REJECT'?'selected':''}>拒绝连接 · REJECT</option></select></div><p class="small muted">会在规则列表顶部添加 DOMAIN 精确匹配规则。应用前可以查看新旧结果。</p>${actions('preview-patch','预览变更')}`);
  }
  function previewPatch() {
    const policy=$('#new-policy',modal).value;
    if(policy===getRoute().policy){notify('结果与当前规则一致，无需应用变更。');return;}
    patch={target:state.target,policy,profileId:state.active,revision:state.revision};
    const old=getRoute();
    const next=policy==='DIRECT'?'直接连接':policy==='REJECT'?'拒绝连接':'proxy/lab-a';
    openDialog('确认路由变更','仅影响当前配置中的这个目标；应用后可撤销。',`<div class="diff"><div><h3>当前结果</h3><p>${esc(old.exit)}</p><p class="muted">${esc(old.policy)}</p></div><div><h3>应用后</h3><p>${esc(next)}</p><p class="muted">${esc(policy)}</p></div></div><code class="source-code">+ DOMAIN, ${esc(patch.target)}, ${esc(policy)}</code><div class="note">${icon('info')}<span>新规则置于列表顶部，仅匹配此域名；其他目标保留原有匹配顺序。</span></div><div class="dialog-actions"><button type="button" class="btn" data-action="edit-rule">返回修改</button><button type="button" class="btn primary" data-action="apply-patch">确认应用</button></div>`);
  }
  const sample='[Proxy]\nlab-a = http, 127.0.0.1, 7890\n\n[Proxy Group]\npolicy-main = select, lab-a\n\n[Rule]\nDOMAIN-SUFFIX, lab.internal, DIRECT\nDOMAIN-SUFFIX, github.com, policy-main\nFINAL, policy-main\n\n[General]\nexternal-policy = example-policy\n\n[URL Rewrite]\n^https://example.com https://example.org 302';
  function importDialog() {
    state.importResult=null;
    openDialog('导入配置','粘贴配置文本，先查看支持范围。原文件不会被修改。',`<div class="note">${icon('info')}<span>原型仅演示有限的 Surge 子集解析，不代表真实引擎兼容性。仅支持一个本地 HTTP 出口、静态 select 组与三类路由规则。</span></div><div class="field"><label for="import-name">新配置名称</label><input type="text" id="import-name" value="imported-profile.yaml" maxlength="80"></div><div class="field"><label for="import-source">配置内容</label><textarea id="import-source" spellcheck="false" placeholder="粘贴配置内容"></textarea></div><button type="button" class="action-link" data-action="fill-sample">填入示例配置</button><div id="import-error" class="note error" role="alert" hidden></div>${actions('preview-import','查看导入预览')}`);
  }
  function parseImport(source) {
    let section=''; const entries=[]; const unsupported=[]; const proxies=[]; const groups=[]; const accepted=[];
    source.split(/\r?\n/).forEach((raw,index)=>{
      const line=raw.trim(); if(!line||line.startsWith('#')||line.startsWith(';'))return;
      const mark=line.match(/^\[([^\]]+)\]$/); if(mark){section=mark[1].toLowerCase();return;}
      const row={line:index+1,text:line,section};
      if(section==='proxy') {
        const m=line.match(/^([^=]+)=\s*http\s*,\s*(127\.0\.0\.1|localhost)\s*,\s*(\d+)\s*$/i);
        if(m&&Number(m[3])>0&&Number(m[3])<=65535&&proxies.length===0) { proxies.push(m[1].trim()); accepted.push(row); } else unsupported.push({...row,reason:'示例仅支持一个本地 HTTP 出口，且不支持附加参数'});
      } else if(section==='proxy group') {
        const m=line.match(/^([^=]+)=\s*select\s*,\s*([^,]+)\s*$/i);
        if(m)groups.push({...row,name:m[1].trim(),member:m[2].trim()}); else unsupported.push({...row,reason:'仅演示单成员 select 策略组'});
      } else if(section==='rule') {
        const parts=line.split(',').map(s=>s.trim());
        const type=parts[0].toUpperCase();
        if((type==='FINAL'&&parts.length===2)||(['DOMAIN','DOMAIN-SUFFIX'].includes(type)&&parts.length===3&&validDomain(parts[1])))entries.push({...row,type,value:type==='FINAL'?'':parts[1].toLowerCase(),policy:parts.at(-1)});
        else unsupported.push({...row,reason:'仅演示 DOMAIN、DOMAIN-SUFFIX 与 FINAL，且不支持附加参数'});
      } else unsupported.push({...row,reason:section==='url rewrite'?'此原型不支持 URL Rewrite':'此配置项不在原型支持范围内'});
    });
    const validGroups=groups.filter(g=>{if(proxies.includes(g.member)){accepted.push(g);return true;}unsupported.push({...g,reason:'策略组引用了未支持的出口'});return false;});
    const policies=new Set(['DIRECT','REJECT',...validGroups.map(g=>g.name),...proxies]);
    const supported=entries.filter(e=>{if(policies.has(e.policy)){accepted.push(e);return true;}unsupported.push({...e,reason:'规则引用了未支持的策略'});return false;});
    const finalIndex=supported.findIndex(e=>e.type==='FINAL');
    const reachable=finalIndex>=0?supported.slice(0,finalIndex+1):supported;
    if(finalIndex>=0) supported.slice(finalIndex+1).forEach(e=>unsupported.push({...e,reason:'位于 FINAL 之后，不会执行'}));
    return {rules:reachable.map(e=>({type:e.type,value:e.value,policy:['DIRECT','REJECT'].includes(e.policy)?e.policy:'policy-main'})),unsupported,proxies:proxies.length,groups:validGroups.length};
  }
  function validDomain(value) { return value.length<=253&&value.split('.').every(s=>s.length>0&&s.length<=63&&/^[a-z0-9](?:[a-z0-9-]*[a-z0-9])?$/i.test(s)); }
  function previewImport() {
    const name=$('#import-name',modal).value.trim();
    const source=$('#import-source',modal).value.trim();
    const result=parseImport(source);
    const error=$('#import-error',modal);
    if(!name||/[\\/:*?"<>|]/.test(name)||state.profiles.some(p=>p.name===name)) { error.textContent='请填写有效且不重复的配置名称，避免斜杠等特殊字符。'; error.hidden=false; return; }
    if(!source||!result.rules.length) { error.textContent='没有找到可导入的路由规则。请填入示例，或补充受支持的规则和策略。';error.hidden=false;return; }
    if(!result.rules.some(r=>r.type==='FINAL')) { error.textContent='缺少可用的 FINAL 兜底规则。请补充后重新预览，避免目标没有出口。';error.hidden=false;return; }
    state.importResult={...result,name};
    openDialog('导入预览','确认保留哪些内容，再创建一份新的示例配置。',`<div class="diff"><div><h3>将导入</h3><p>${result.rules.length} 条路由规则</p><p>${result.proxies} 个本地 HTTP 出口</p><p>${result.groups} 个静态策略组</p></div><div><h3>${result.unsupported.length?'有内容未导入':'无需排除内容'}</h3><p>${result.unsupported.length} 条配置内容</p><p class="muted">${result.unsupported.length?'下方逐项说明原因。':'所有条目均在示例支持范围内。'}</p></div></div>${result.unsupported.length?`<div><h3>未导入内容</h3><ul class="report-list">${result.unsupported.map(r=>`<li><strong>第 ${r.line} 行：${esc(r.text)}</strong><br><span class="muted">${esc(r.reason)}</span></li>`).join('')}</ul></div><label class="check-label"><input type="checkbox" id="import-ack"><span>我已了解这些内容不会导入；新配置可能与原配置行为不同。</span></label>`:''}<p class="small muted">代理与策略在本地示例中统一映射为 policy-main → proxy/lab-a，不用于真实网络连接。</p><div class="dialog-actions"><button type="button" class="btn" data-action="back-import">返回修改</button><button type="button" class="btn primary" data-action="confirm-import" ${result.unsupported.length?'disabled':''}>创建配置</button></div>`);
    state.importResult.source=source;
  }
  function validateRules(list) {
    const errors=[];
    if(!list.length)errors.push('没有路由规则。请至少添加一条 FINAL 兜底规则。');
    list.forEach((r,i)=>{
      if(!['DOMAIN','DOMAIN-SUFFIX','FINAL'].includes(r.type))errors.push(`第 ${i+1} 条：不支持的规则类型。`);
      if(r.type!=='FINAL'&&!validDomain(r.value))errors.push(`第 ${i+1} 条：域名格式无效。`);
      if(!['DIRECT','REJECT','policy-main'].includes(r.policy))errors.push(`第 ${i+1} 条：请选择 DIRECT、REJECT 或 policy-main。`);
    });
    const final=list.findIndex(r=>r.type==='FINAL');
    if(list.length&&final<0)errors.push('缺少 FINAL 兜底规则。请在最后添加 FINAL, policy-main，避免其他目标没有出口。');
    if(final>=0&&final!==list.length-1)errors.push('FINAL 必须是最后一条规则，否则后面的规则不会执行。');
    return errors;
  }
  let profileDraft=null;
  function editProfile() {
    const p=chosen();profileDraft={id:p.id,revision:state.revision,rules:null};
    openDialog('编辑路由规则','每行一条规则；保存前先校验，并查看变更范围。',`<p class="mono">${esc(p.name)}</p><div class="field"><label for="rules-source">规则内容</label><textarea id="rules-source" spellcheck="false">${esc(p.rules.map(r=>[r.type,...(r.type==='FINAL'?[]:[r.value]),r.policy].join(', ')).join('\n'))}</textarea></div><p class="small muted">支持 DOMAIN、DOMAIN-SUFFIX、FINAL；策略为 DIRECT、REJECT 或 policy-main。</p><button type="button" class="action-link" data-action="append-final">添加默认转发规则</button><div id="rules-error" class="note error" role="alert" hidden></div>${actions('preview-profile','校验并预览')}`);
  }
  function previewProfile() {
    const text=$('#rules-source',modal).value;const list=[];const errors=[];
    text.split(/\r?\n/).forEach((line,index)=>{if(!line.trim())return;const parts=line.split(',').map(v=>v.trim());const type=parts[0].toUpperCase();if(parts.length!==(type==='FINAL'?2:3)){errors.push(`第 ${index+1} 行：字段数量不正确。`);return;}list.push({type,value:type==='FINAL'?'':parts[1].toLowerCase(),policy:parts.at(-1)});});
    errors.push(...validateRules(list));
    if(errors.length){const box=$('#rules-error',modal);box.innerHTML=`<div><strong>请先修正以下问题</strong><ul class="report-list">${errors.map(e=>`<li>${esc(e)}</li>`).join('')}</ul></div>`;box.hidden=false;$('#rules-source',modal).setAttribute('aria-invalid','true');return;}
    profileDraft.rules=list;profileDraft.text=text;
    const p=state.profiles.find(p=>p.id===profileDraft.id);
    openDialog('确认规则变更','保存后重新计算路由，支持撤销。',`<p class="mono">${esc(p.name)}</p><div class="diff"><div><h3>当前规则</h3><code class="source-code">${esc(p.rules.map(r=>[r.type,...(r.type==='FINAL'?[]:[r.value]),r.policy].join(', ')).join('\n')||'无')}</code></div><div><h3>保存后</h3><code class="source-code">${esc(text)}</code></div></div><p class="small muted">${p.id===state.active?'正在修改当前使用的配置，保存后立即影响路由计算。':'只修改这份配置，不会自动切换使用。'}</p><div class="dialog-actions"><button type="button" class="btn" data-action="back-profile">返回修改</button><button type="button" class="btn primary" data-action="save-profile">确认保存</button></div>`);
  }
  function commandItems() {
    return [
      ...Object.entries(names).map(([id,label])=>({label,description:'页面',search:label+' '+id,view:id})),
      ...state.profiles.map(p=>({label:p.name,description:p.description,search:p.name+' '+p.description,profile:p.id})),
      ...['nas.lab.internal','github.com'].map(target=>({label:target,description:'检查目标路由',search:target+' 路由',target}))
    ].filter(item=>matchText(state.commandQuery,item.search));
  }
  function commandResults() {
    const items=commandItems();
    return items.length?items.map(item=>`<button type="button" class="command-item" ${item.view?`data-command-view="${item.view}"`:item.profile?`data-open-profile="${esc(item.profile)}"`:`data-target="${esc(item.target)}"`}><span class="od-field od-fill"><strong>${esc(item.label)}</strong><span>${esc(item.description)}</span></span>${icon('arrow')}</button>`).join(''):'<div class="empty">没有匹配项。试试配置名称、域名或页面名称。</div>';
  }
  function commands() {
    state.commandQuery='';
    openDialog('快速查找','页面、配置与已保存目标。',`<div class="field"><label for="command-search">查找内容</label><input type="search" id="command-search" autocomplete="off" placeholder="输入配置名称、域名或页面名称"></div><div id="command-results" class="command-results" aria-label="查找结果">${commandResults()}</div><p class="small muted">↑ ↓ 选择 · Enter 打开 · Esc 关闭</p>`);
    $('#command-search',modal).focus();
  }
  function diagnostic() {
    const r=getRoute();
    return {kind:'relaypilot-prototype-diagnostic',simulation:true,networkCaptured:false,target:state.redact?'[redacted]':state.target,matchedRule:r.rule?{type:r.rule.type,policy:r.policy,...(state.redact?{}:{value:r.rule.value})}:null,result:r.exit,revision:state.revision,...(state.redact?{}:{trace_id:traceId()})};
  }
  function inspect() {
    const input=$('#target',root); const value=input.value.trim().toLowerCase(); state.input=value;
    const error=$('#target-error',root);
    if(!validDomain(value)){error.textContent='请输入域名，例如 nas.lab.internal；不要包含协议、路径或空格。';error.hidden=false;input.setAttribute('aria-invalid','true');input.focus();return;}
    state.target=value;state.inspecting=true;render();
    const token=++state.inspectionToken;setTimeout(()=>{if(token!==state.inspectionToken)return;state.inspecting=false;render();$('#target',root)?.focus();},450);
  }
  async function handle(action) {
    if(action==='dismiss'){toast.hidden=true;return;}
    if(action==='close-modal'){closeDialog();return;}
    if(action==='session'){confirmSession();return;}
    if(action==='commands'){commands();return;}
    if(action==='clear-filters'){state.query='';state.filter='all';render();$('#profile-search',root)?.focus();return;}
    if(action==='start-session') {
      closeDialog();state.session='starting';const token=++state.connectionToken;event('开始校验示例规则。');render();
      setTimeout(()=>{if(token!==state.connectionToken)return;const errors=validateRules(active().rules);if(errors.length){state.session='idle';active().status='invalid';active().errors=errors;event('配置校验失败，会话未启动。');render();notify('配置校验失败，请在待处理事项中修正。');return;}state.session='running';event('会话已启动。');render();notify('会话已启动。');},950);return;
    }
    if(action==='stop-session'){closeDialog();state.session='idle';++state.connectionToken;event('会话已停止。');render();notify('会话已停止。');return;}
    if(action==='choose-profile'){openProfile(state.active);return;}
    if(action==='inspect'){inspect();return;}
    if(action==='edit-rule'){editRule();return;}
    if(action==='preview-patch'){previewPatch();return;}
    if(action==='apply-patch') {
      if(!patch||patch.profileId!==state.active||patch.revision!==state.revision){closeDialog();notify('配置已经变化，请重新预览。');return;}
      state.undo=snapshot();const p=active();p.rules=p.rules.filter(r=>!(r.type==='DOMAIN'&&r.value===patch.target));p.rules.unshift({type:'DOMAIN',value:patch.target,policy:patch.policy});state.revision++;event('已应用目标路由变更。');closeDialog();render();notify('规则已应用，路由结果已更新。',true);return;
    }
    if(action==='undo') { if(state.undo){const nextRevision=state.revision+1;Object.assign(state,state.undo);state.undo=null;state.revision=nextRevision;if(state.view==='profiles'&&!filteredProfiles().some(p=>p.id===state.selected)){state.query='';state.filter='all';}event('上一项配置变更已撤销。');render();$('[data-action="commands"]',root)?.focus();notify('已恢复上一版配置。');}return; }
    if(action==='copy-trace') {
      const r=getRoute();const text=`RelayPilot 本地模拟\ntrace_id: ${traceId()}\n目标: ${state.target}\n规则: ${r.source}\n结果: ${r.exit}\n真实引擎: 未调用`;
      try{await navigator.clipboard.writeText(text);notify('检查记录已复制。');}catch(_){openDialog('复制检查记录','浏览器未允许直接复制，请选择下方文本手动复制。',`<textarea aria-label="检查记录" readonly>${esc(text)}</textarea><div class="dialog-actions"><button class="btn" type="button" data-action="close-modal">完成</button></div>`);$('textarea',modal).select();}return;
    }
    if(action==='validate-profile') {const p=chosen();const errors=validateRules(p.rules);p.status=errors.length?'invalid':'valid';p.errors=errors;if(state.filter!=='all'&&state.filter!==p.status)state.filter='all';event((errors.length?'配置校验失败：':'配置校验通过：')+p.name);render();(errors.length?$('[data-action="edit-profile"]',root):$('[data-action="use-profile"]',root))?.focus();notify(errors.length?'校验未通过，详情中有具体修复方法。':'校验通过，可选择使用。');return;}
    if(action==='edit-profile'){editProfile();return;}
    if(action==='append-final'){const input=$('#rules-source',modal);input.value=input.value.trim()+'\nFINAL, policy-main';input.focus();return;}
    if(action==='preview-profile'){previewProfile();return;}
    if(action==='back-profile'){const draft=profileDraft;state.selected=draft.id;editProfile();$('#rules-source',modal).value=draft.text;return;}
    if(action==='save-profile'){
      const draft=profileDraft;const p=state.profiles.find(p=>p.id===draft?.id);
      if(!p||!draft.rules||draft.revision!==state.revision){closeDialog();notify('配置已经变化，请重新预览。');return;}
      state.undo=snapshot();p.rules=draft.rules;p.status='valid';p.errors=[];if(state.filter!=='all'&&state.filter!=='valid')state.filter='all';state.revision++;event('规则已保存：'+p.name);closeDialog();render();notify('规则已保存，校验通过。',true);return;
    }
    if(action==='use-profile') {const p=chosen();if(p.status!=='valid')return;openDialog('切换当前配置？',running()?'演示会话将使用新的示例配置。':'切换后会用于后续路由检查。',`<div class="diff"><div><h3>当前配置</h3><p>${esc(active().name)}</p></div><div><h3>切换为</h3><p>${esc(p.name)}</p></div></div>${actions('confirm-profile','确认切换')}`);return;}
    if(action==='confirm-profile') {if(chosen().status!=='valid')return;state.undo=snapshot();state.active=chosen().id;state.revision++;event('当前配置已切换为 '+active().name);closeDialog();render();notify('当前配置已切换。',true);return;}
    if(action==='delete-profile') {openDialog('删除这份配置？','只删除本次原型会话中的副本，不影响真实文件。',`<p class="mono">${esc(chosen().name)}</p>${actions('confirm-delete','确认删除')}`);return;}
    if(action==='confirm-delete') {if(state.selected===state.active)return;state.undo=snapshot();state.profiles=state.profiles.filter(p=>p.id!==state.selected);state.selected=state.active;state.query='';state.filter='all';closeDialog();render();notify('配置已删除。',true);return;}
    if(action==='import'){importDialog();return;}
    if(action==='fill-sample'){$('#import-source',modal).value=sample;$('#import-error',modal).hidden=true;return;}
    if(action==='preview-import'){previewImport();return;}
    if(action==='back-import'){const previous=state.importResult;importDialog();if(previous){$('#import-name',modal).value=previous.name;$('#import-source',modal).value=previous.source;}return;}
    if(action==='confirm-import') {
      const result=state.importResult;if(!result||result.unsupported.length&&!$('#import-ack',modal)?.checked)return;
      state.undo=snapshot();const id='import-'+Date.now();state.profiles.push({id,name:result.name,status:'valid',description:'已确认的导入示例',rules:result.rules});state.selected=id;state.query='';state.filter='all';state.view='profiles';state.importResult=null;event('已创建导入配置，当前运行配置未切换。');closeDialog();render();notify('新配置已创建，尚未切换使用。',true);return;
    }
    if(action==='redact'){state.redact=!state.redact;storePreferences();render();$('[data-action="redact"]',root)?.focus();notify(state.redact?'导出时将隐藏目标地址。':'导出将包含示例目标地址。');return;}
    if(action==='export') {
      const blob=new Blob([JSON.stringify(diagnostic(),null,2)],{type:'application/json'});const url=URL.createObjectURL(blob);const a=document.createElement('a');a.href=url;a.download='relaypilot-demo-diagnostic.json';document.body.append(a);a.click();a.remove();setTimeout(()=>URL.revokeObjectURL(url),1500);notify('已请求下载演示诊断记录。');return;
    }
  }
  document.addEventListener('click',e=>{
    if(surface!=='desktop')return;
    const b=e.target.closest('button');if(!b||b.disabled)return;
    if(b.dataset.commandView){closeDialog();go(b.dataset.commandView);return;}
    if(b.dataset.view){go(b.dataset.view);return;}
    if(b.dataset.openProfile){closeDialog();openProfile(b.dataset.openProfile);return;}
    if(b.dataset.target){closeDialog();++state.inspectionToken;state.target=b.dataset.target;state.input=state.target;state.inspecting=false;go('trace');return;}
    if(b.dataset.profile){state.selected=b.dataset.profile;$('#profile-results',root).innerHTML=profileResults();$(`[data-profile="${state.selected}"]`,root)?.focus();return;}
    if(b.dataset.action)handle(b.dataset.action);
  });
  document.addEventListener('input',e=>{
    if(surface!=='desktop')return;
    if(e.target.id==='target')state.input=e.target.value;
    if(e.target.id==='profile-search'){state.query=e.target.value;$('#profile-results',root).innerHTML=profileResults();}
    if(e.target.id==='command-search'){state.commandQuery=e.target.value;$('#command-results',modal).innerHTML=commandResults();}
  });
  document.addEventListener('change',e=>{
    if(surface!=='desktop')return;
    if(e.target.id==='theme'){state.theme=e.target.value;setTheme();storePreferences();notify('外观偏好已更新。');}
    if(e.target.id==='import-ack'){const b=$('[data-action="confirm-import"]',modal);if(b)b.disabled=!e.target.checked;}
    if(e.target.id==='profile-filter'){state.filter=e.target.value;$('#profile-results',root).innerHTML=profileResults();}
    if(e.target.id==='expected-policy'){const value=e.target.value;if(value)state.expected[state.target]=value;else delete state.expected[state.target];render();$('#expected-policy',root)?.focus();}
  });
  document.addEventListener('keydown',e=>{
    if(surface!=='desktop'||e.isComposing||e.repeat)return;
    if((e.metaKey||e.ctrlKey)&&e.key.toLowerCase()==='k'){e.preventDefault();if(!modal.open)commands();return;}
    if(modal.open&&$('#command-search',modal)){
      const buttons=Array.from(modal.querySelectorAll('.command-item'));
      const index=buttons.indexOf(document.activeElement);
      if(['ArrowDown','ArrowUp'].includes(e.key)){e.preventDefault();if(buttons.length){const next=index<0?(e.key==='ArrowDown'?0:buttons.length-1):(index+(e.key==='ArrowDown'?1:-1)+buttons.length)%buttons.length;buttons[next].focus();}return;}
      if(e.key==='Enter'&&e.target.id==='command-search'){e.preventDefault();buttons[0]?.click();return;}
    }
    if(modal.open)return;
    const editable=e.target.closest('input,textarea,select,[contenteditable]');
    if(e.key==='/'&&!editable&&!modal.open&&!e.metaKey&&!e.ctrlKey&&!e.altKey){e.preventDefault();if(state.view==='trace')$('#target',root)?.focus();else{if(state.view!=='profiles')go('profiles',false);$('#profile-search',root)?.focus();}return;}
    if(e.key==='Enter'&&e.target.id==='target'){e.preventDefault();if(!state.inspecting)inspect();}
  });
  function initMobile() {
    const mobileNames={connect:'运行概览',trace:'路由检查',profiles:'配置库',settings:'设置'};
    const mobileFiles={connect:'mobile-overview.html',trace:'mobile-trace.html',profiles:'mobile-profiles.html',settings:'mobile-settings.html'};
    const m={desktop:'offline',proxy:'stopped',checking:false,input:'',result:null,records:[],detail:null,query:'',stack:[],scroll:{},error:'',request:0,readingProcess:false};
    const scenario=new URLSearchParams(location.search).get('scenario') || 'offline';
    if(['running','starting','stopping','proxy-failed','invalid','process-unreachable','stopped'].includes(scenario))m.desktop='online';
    if(['running','starting','stopping'].includes(scenario))m.proxy=scenario;
    if(scenario==='failed'){m.desktop='failed';m.error='无法连接桌面控制端。请确认桌面已开机、RelayPilot 正在运行，且两端位于可达网络。';}
    if(scenario==='proxy-failed'){m.proxy='failed';m.error='桌面未能启动 Xray。请在桌面查看进程诊断，处理后重新尝试。';}
    if(scenario==='process-unreachable'){m.proxy='unreachable';m.error='桌面控制端可达，但无法读取 Xray 进程状态。请在桌面检查进程和控制权限。';}
    if(scenario==='invalid'){state.active='office';state.selected='office';active().status='invalid';active().errors=validateRules(active().rules);m.error='配置校验失败，代理尚未启动。';}
    const online=()=>m.desktop==='online';
    const working=()=>['starting','stopping'].includes(m.proxy)||m.desktop==='connecting';
    const routeKey=()=>state.view+(m.detail?':'+m.detail:'');
    function savePosition(){m.scroll[routeKey()]=window.scrollY;}
    function navigate(view,detail=null,push=true){
      savePosition();if(push)m.stack.push({view:state.view,detail:m.detail});
      state.view=view;m.detail=detail;draw();window.scrollTo(0,m.scroll[routeKey()]||0);
      $('h1',root)?.focus({preventScroll:true});
    }
    function back(){const previous=m.stack.pop();if(previous)navigate(previous.view,previous.detail,false);else if(m.detail)navigate('profiles',null,false);else if(state.view!=='connect')navigate('connect',null,false);else location.href='../index.html';}
    const link=(view,label,desc)=>`<a href="${mobileFiles[view]}" class="m-row" data-m-view="${view}"><span class="od-field od-fill"><strong>${label}</strong><span class="m-meta">${desc}</span></span>${icon('arrow')}</a>`;
    const stateLabel=()=>!online()?'状态未知':({running:'运行中',stopped:'已停止',starting:'启动中',stopping:'停止中',failed:'连接失败',unreachable:'进程不可达'}[m.proxy]);
    function frame(content){
      return `<div class="m-app"><header class="m-header"><button type="button" class="m-back" data-m-action="back">${icon('back')}<span>${m.detail?'配置库':state.view==='connect'?'原型目录':'返回'}</span></button><span class="m-meta">RelayPilot · 桌面伴随端</span></header><main class="m-main"><h1 tabindex="-1">${m.detail?'配置详情':mobileNames[state.view]}</h1><p class="m-caption">${m.detail?'查看桌面配置，不在手机修改。':state.view==='connect'?'控制桌面的代理，连接始终发生在桌面。':state.view==='trace'?'按桌面配置检查目标的路由。':state.view==='profiles'?'配置存放在桌面，手机以只读查看为主。':'外观与桌面连接信息。'}</p><div class="m-prototype">本地交互模拟 · 未连接真实桌面</div>${content}</main></div>`;
    }
    function offlineContent(){
      const failed=m.desktop==='failed';
      return `<section class="m-empty" aria-label="桌面连接状态"><span class="m-state-icon">${icon(failed?'warning':'grid')}</span><h2>${m.desktop==='connecting'?'正在连接桌面':failed?'连接失败':'桌面不在线'}</h2><p>${m.desktop==='connecting'?'正在尝试读取桌面状态，请稍候。':failed?esc(m.error):'尚未取得桌面状态。请确认桌面已开机，并打开 RelayPilot。'}</p><button type="button" class="btn primary" data-m-action="reconnect" ${m.desktop==='connecting'?'disabled':''}>${m.desktop==='connecting'?'正在连接…':failed?'重新连接':'连接桌面'}</button><p class="m-meta">离线时无法启停代理或检查新的路由。</p></section>`;
    }
    function mobileOverview(){
      if(!online())return offlineContent()+`<nav class="m-section" aria-label="伴随端功能">${link('trace','路由检查','输入与最近记录保留')}${link('profiles','配置库','查看本地示例，不代表实时快照')}${link('settings','设置','主题与连接说明')}</nav>`;
      const invalid=active().status==='invalid';
      const danger=['failed','unreachable'].includes(m.proxy);
      const fallback=active().rules.find(r=>r.type==='FINAL');
      const exit=m.proxy==='running'?(fallback?.policy==='DIRECT'?'DIRECT':fallback?.policy==='REJECT'?'REJECT':'proxy/lab-a'):'未启用';
      return `<section class="m-panel" aria-label="桌面代理状态"><div class="od-row"><span class="m-state-icon ${m.proxy==='running'?'good':danger?'bad':''}">${icon(m.proxy==='running'?'check':danger?'warning':'power')}</span><div class="od-field od-fill"><span class="m-meta">家庭实验室桌面 · 示例</span><h2 class="m-status" role="status">${stateLabel()}</h2></div></div><p class="m-caption">${working()?(m.proxy==='starting'?'正在校验桌面配置并启动 Xray。':'正在等待桌面停止 Xray。'):danger?esc(m.error):m.proxy==='running'?'Xray 在桌面运行，手机不承载代理进程。':'Xray 已停止，配置仍保留在桌面。'}</p>${danger?`<button type="button" class="btn primary m-full" data-m-action="${m.proxy==='unreachable'?'refresh-process':'control'}" ${m.readingProcess?'disabled':''}>${m.readingProcess?'正在读取…':m.proxy==='unreachable'?'重新读取进程状态':'重试启动'}</button>`:`<button type="button" class="btn ${m.proxy==='running'?'danger':'primary'} m-full" data-m-action="control" ${working()?'disabled':''}>${icon('power')}${working()?m.proxy==='starting'?'正在启动…':'正在停止…':m.proxy==='running'?'停止桌面代理':'启动桌面代理'}</button>`}<dl class="m-facts"><div><dt>当前出口</dt><dd class="mono">${exit}</dd></div><div><dt>出口延迟</dt><dd>未测量</dd></div><div><dt>当前配置</dt><dd class="mono">${esc(active().name)}</dd></div></dl></section>${invalid?`<section class="m-feedback error" role="alert">${icon('warning')}<div class="od-field od-fill"><strong>校验失败，未启动</strong><span>缺少 FINAL 兜底规则。请在桌面修复后再重试。</span><button type="button" class="m-text-button" data-m-profile="office">查看错误详情 ${icon('arrow')}</button></div></section>`:''}<nav class="m-section" aria-label="伴随端功能">${link('trace','路由检查','查看命中规则与最终策略')}${link('profiles','配置库',state.profiles.length+' 份示例配置 · 只读')}${link('settings','设置','主题与桌面连接')}</nav>`;
    }
    function mobileTrace(){
      const unavailable=!online()||m.proxy==='unreachable';
      const r=m.result;
      return `${unavailable?`<div class="m-feedback warn">${icon('warning')}<div class="od-field"><strong>${online()?'Xray 进程不可达':'桌面不在线'}</strong><span>无法读取新的路由结果，输入和已有记录会保留。</span><button type="button" class="m-text-button" data-m-view="connect">返回概览处理 ${icon('arrow')}</button></div></div>`:''}<div class="m-section field"><label for="m-target">目标域名</label><input type="text" class="mono" id="m-target" autocomplete="off" autocapitalize="none" spellcheck="false" inputmode="url" value="${esc(m.input)}" placeholder="例如 nas.lab.internal" aria-describedby="m-target-error"><p class="field-error" id="m-target-error" role="alert" hidden></p><button type="button" class="btn primary" data-m-action="inspect" ${unavailable||m.checking?'disabled':''}>${icon('search')}${m.checking?'正在检查…':'检查路由'}</button></div>${m.checking?'<div class="m-feedback" role="status">正在按顺序匹配规则…</div>':r?`<section class="m-section m-panel"><div class="section-head"><h2>检查结果</h2>${badge(r.matchedKind==='FINAL'?'兜底匹配':r.matchedKind?'规则命中':'未匹配',r.matchedKind?'ok':'warn')}</div><p class="mono">${esc(r.target)}</p><dl class="m-facts"><div><dt>matchedKind</dt><dd class="mono">${esc(r.matchedKind||'无')}</dd></div><div><dt>命中规则</dt><dd class="mono">${esc(r.source||'无匹配规则')}</dd></div><div><dt>最终策略</dt><dd class="mono">${esc(r.policy)}</dd></div><div><dt>出口</dt><dd class="mono">${esc(r.exit)}</dd></div></dl><p class="m-meta">${r.policy==='DIRECT'?'DIRECT 命中后停止，不再选择代理出口。':r.policy==='REJECT'?'REJECT 命中后终止，不再选择出口。':'按规则顺序首条命中即停止，策略组解析到静态示例出口。'}</p><details><summary>规则来源与记录</summary><code class="source-code">${esc(r.profile)} · rules[${r.index}]\n${esc(r.traceId)}\n${esc(r.source)}</code><p class="m-meta">本地规则模拟，无真实引擎摘要。</p></details>${unavailable?'<p class="m-meta">上次检查结果，当前桌面状态不可用。</p>':''}</section>`:'<p class="m-meta m-section">输入一个域名，查看配置中第一条命中的规则。</p>'}<section class="m-section"><h2>最近检查</h2>${m.records.length?m.records.map((record,i)=>`<button type="button" class="m-row" data-m-record="${i}"><span class="od-field od-fill"><strong class="mono">${esc(record.target)}</strong><span class="m-meta">${esc(record.policy)} · ${esc(record.time)}</span></span>${icon('arrow')}</button>`).join(''):'<div class="m-empty-compact"><p>还没有检查记录</p><p class="m-meta">成功完成检查后，结果会保留在这里。</p></div>'}</section>`;
    }
    function mobileProfiles(){
      const p=m.detail?state.profiles.find(p=>p.id===m.detail):null;
      const note=!online()?'<div class="m-feedback warn">桌面不在线。以下为本地示例，不能作为实时桌面状态。</div>':'';
      if(p){
        const errors=p.status==='invalid'?(p.errors||validateRules(p.rules)):[];
        return `${note}<section class="m-section"><div class="section-head"><h2 class="mono">${esc(p.name)}</h2>${badge(p.status==='valid'?'校验通过':p.status==='pending'?'待校验':'校验失败',p.status==='valid'?'ok':p.status==='pending'?'warn':'error')}</div><p class="m-caption">${esc(p.description)}${p.id===state.active?' · 桌面当前配置':''}</p>${errors.length?`<div class="m-feedback error" role="status"><div class="od-field"><strong>请在桌面处理</strong><ul class="report-list">${errors.map(e=>`<li>${esc(e)}</li>`).join('')}</ul></div></div>`:''}<h3 class="m-section">路由规则</h3>${p.rules.length?p.rules.map((r,i)=>`<div class="m-rule"><span class="m-meta mono">${i+1}</span><div class="od-field od-fill"><code>${esc(r.type)}${r.value?', '+esc(r.value):''}</code><span class="mono">${esc(r.policy)}</span></div></div>`).join(''):'<p class="m-caption">完整配置尚未转换，请在桌面查看逐行导入报告。</p>'}<p class="m-meta m-section">只读查看。修改、导入、切换和删除配置请在桌面完成。</p></section>`;
      }
      return `${note}<div class="field m-section"><label for="m-profile-search">搜索配置</label><input type="search" id="m-profile-search" value="${esc(m.query)}" placeholder="搜索名称或描述"></div><div id="m-profile-list">${profileList()}</div><p class="m-meta m-section">导入不会自动切换当前配置。校验失败需在桌面修复，手机不修改配置。</p>`;
    }
    function profileList(){
      const list=state.profiles.filter(p=>matchText(m.query,p.name+' '+p.description));
      return list.length?list.map(p=>`<button type="button" class="m-row" data-m-profile="${p.id}"><span class="od-field od-fill"><strong class="mono">${esc(p.name)}</strong><span class="m-meta">${esc(p.description)}${p.id===state.active?' · 当前配置':''}</span><span>${badge(p.status==='valid'?'校验通过':p.status==='pending'?'待校验':'校验失败',p.status==='valid'?'ok':p.status==='pending'?'warn':'error')}</span></span>${icon('arrow')}</button>`).join(''):'<div class="m-empty-compact"><p>没有匹配的配置</p><button type="button" class="m-text-button" data-m-action="clear-search">清除搜索</button></div>';
    }
    function mobileSettings(){
      return `<section class="m-section"><h2>外观</h2><div class="field m-setting"><label for="m-theme">主题</label><select id="m-theme">${[['system','跟随系统'],['light','浅色'],['dark','深色']].map(([v,n])=>`<option value="${v}" ${state.theme===v?'selected':''}>${n}</option>`).join('')}</select></div></section><section class="m-section"><h2>桌面连接</h2><div class="m-setting od-field"><strong>家庭实验室桌面</strong><span class="m-meta">${online()?'控制端可达 · 示例状态':'尚未连接桌面'}</span></div><dl class="m-facts"><div><dt>代理进程</dt><dd class="mono">Xray · ${stateLabel()}</dd></div><div><dt>配置归属</dt><dd>存放在桌面</dd></div></dl><button type="button" class="m-text-button" data-m-view="connect">查看桌面状态 ${icon('arrow')}</button></section><section class="m-section"><h2>控制范围</h2><p class="m-caption">此原型展示状态查看、启停与路由检查。配置以只读呈现。</p><p class="m-meta">实际配对、认证以及远端只读或全量控制权限，随实现立项另定。</p></section><section class="m-section"><h2>隐私</h2><div class="m-setting od-row"><div class="od-field od-fill"><strong id="m-redact-label">诊断目标脱敏</strong><span class="m-meta">沿用桌面偏好，不传输真实配置。</span></div><button type="button" class="switch" role="switch" aria-checked="${state.redact}" aria-labelledby="m-redact-label" data-m-action="redact">${state.redact?'已开启':'已关闭'}${icon(state.redact?'check':'close')}</button></div></section>`;
    }
    function draw(){root.innerHTML=frame(({connect:mobileOverview,trace:mobileTrace,profiles:mobileProfiles,settings:mobileSettings})[state.view]());}
    function connect(){
      if(working())return;const request=++m.request;m.desktop='connecting';m.error='';draw();
      setTimeout(()=>{if(request!==m.request)return;m.desktop='online';m.proxy='stopped';draw();$('[data-m-action="control"]',root)?.focus();},700);
    }
    function performControl(){
      if(!online()||working())return;
      const stop=m.proxy==='running';
      openDialog(stop?'停止桌面代理？':'启动桌面代理？',stop?'停止后保留桌面配置。':'先校验桌面配置，再启动 Xray。',`<p class="mono">${esc(active().name)}</p><p class="m-meta">原型模拟控制请求，不操作真实桌面。</p><div class="dialog-actions"><button type="button" class="btn" data-m-action="cancel">取消</button><button type="button" class="btn primary" data-m-action="confirm-control">${stop?'确认停止':'确认启动'}</button></div>`);
    }
    function finishControl(stop,request){
      if(request!==m.request||!online())return;
      if(!stop){const errors=validateRules(active().rules);if(errors.length){active().status='invalid';active().errors=errors;m.proxy='stopped';m.error='配置校验失败，代理尚未启动。';draw();return;}}
      m.proxy=stop?'stopped':'running';m.error='';draw();$('[data-m-action="control"]',root)?.focus();
    }
    function inspectMobile(){
      if(!online()||m.proxy==='unreachable'||m.checking)return;
      const input=$('#m-target',root);const value=input.value.trim().toLowerCase();m.input=value;
      if(!validDomain(value)){const error=$('#m-target-error',root);error.textContent='请输入域名，不要包含协议、路径或空格。';error.hidden=false;input.setAttribute('aria-invalid','true');input.focus();return;}
      m.checking=true;draw();
      setTimeout(()=>{
        m.checking=false;state.target=value;const r=getRoute(value);
        const record={target:value,matchedKind:r.matchedKind,policy:r.policy,exit:r.exit,source:r.source,index:r.index,profile:active().name,traceId:traceId(),time:new Date().toLocaleTimeString('zh-CN',{hour:'2-digit',minute:'2-digit',hour12:false})};
        m.result=record;m.records=[record,...m.records.filter(r=>r.target!==value)].slice(0,8);draw();$('#m-target',root)?.focus();
      },450);
    }
    root.addEventListener('click',e=>{
      const record=e.target.closest('[data-m-record]');
      const profile=e.target.closest('[data-m-profile]');
      const view=e.target.closest('[data-m-view]');
      if(record){const r=m.records[Number(record.dataset.mRecord)];m.result=r;m.input=r.target;draw();$('#m-target',root)?.focus();return;}
      if(profile){navigate('profiles',profile.dataset.mProfile);return;}
      if(view){e.preventDefault();navigate(view.dataset.mView);return;}
    });
    document.addEventListener('click',e=>{
      if(e.target.closest('[data-action="close-modal"]')){closeDialog();return;}
      const b=e.target.closest('[data-m-action]');if(!b||b.disabled)return;
      switch(b.dataset.mAction){
        case 'back':back();break;
        case 'reconnect':connect();break;
        case 'control':performControl();break;
        case 'cancel':closeDialog();break;
        case 'confirm-control':{
          const stop=m.proxy==='running';closeDialog();m.proxy=stop?'stopping':'starting';const request=++m.request;draw();setTimeout(()=>finishControl(stop,request),800);break;
        }
        case 'refresh-process':if(m.readingProcess)return;m.readingProcess=true;m.error='正在重新读取进程状态…';draw();setTimeout(()=>{m.readingProcess=false;m.proxy='stopped';m.error='';draw();},650);break;
        case 'inspect':inspectMobile();break;
        case 'redact':state.redact=!state.redact;storePreferences();draw();$('[data-m-action="redact"]',root)?.focus();break;
        case 'clear-search':m.query='';draw();$('#m-profile-search',root)?.focus();break;
      }
    });
    document.addEventListener('input',e=>{if(e.target.id==='m-target')m.input=e.target.value;if(e.target.id==='m-profile-search'){m.query=e.target.value;$('#m-profile-list',root).innerHTML=profileList();}});
    document.addEventListener('change',e=>{if(e.target.id==='m-theme'){state.theme=e.target.value;setTheme();storePreferences();}});
    document.addEventListener('keydown',e=>{if(e.isComposing||e.repeat)return;if(e.key==='Enter'&&e.target.id==='m-target'){e.preventDefault();inspectMobile();}});
    modal.addEventListener('close',()=>{if(!document.activeElement||document.activeElement===document.body)$('[data-m-action="control"]',root)?.focus();});
    draw();
    if(['starting','stopping'].includes(scenario)){const request=++m.request;setTimeout(()=>finishControl(scenario==='stopping',request),1800);}
  }
  function initDirectory(){
    const select=document.getElementById('directory-theme');
    if(select){select.value=state.theme;select.addEventListener('change',()=>{state.theme=select.value;setTheme();storePreferences();});}
  }

  if(surface==='mobile')initMobile();else if(surface==='directory')initDirectory();else render();
})();
