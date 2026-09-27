/* 广应科课表 —— README 界面稿渲染脚本
   数值来源：lib/widgets/timetable_grid.dart（节高 62 / 休息行 26 / 时间轴 40 / 卡片内缩 3）、
   lib/models/period.dart（节次时间）、lib/theme/course_palette.dart（配色）、
   lib/screens/*.dart（各页文案与字号）。 */

const C = {
  textPrimary: '#1F2430',
  textSecondary: '#8A8F9C',
  today: '#2C63D4',
};

const PH = 62;   // 每节高度
const BH = 26;   // 休息行高度
const GUT = 40;  // 时间轴宽度
const BREAK_AT = [4, 8];

const PERIODS = [
  { n: '第一节', s: '08:20', e: '09:05' },
  { n: '第二节', s: '09:10', e: '09:55' },
  { n: '第三节', s: '10:15', e: '11:00' },
  { n: '第四节', s: '11:05', e: '11:50', brk: '午休' },
  { n: '第五节', s: '14:30', e: '15:15' },
  { n: '第六节', s: '15:20', e: '16:05' },
  { n: '第七节', s: '16:25', e: '17:10' },
  { n: '第八节', s: '17:15', e: '18:00', brk: '晚休' },
  { n: '第九节', s: '19:00', e: '19:45' },
  { n: '第十节', s: '19:50', e: '20:35' },
  { n: '第十一节', s: '20:40', e: '21:25' },
];

const topOf = (i) => (i - 1) * PH + BREAK_AT.filter((b) => b < i).length * BH;
const heightOf = (a, b) =>
  (b - a + 1) * PH + BREAK_AT.filter((x) => x >= a && x < b).length * BH;

const PALETTE = {
  blue: ['#E4EDFD', '#2C63D4'],
  green: ['#E3F3E7', '#2C7A45'],
  yellow: ['#FBF3D6', '#9C7A1B'],
  cyan: ['#DCF2ED', '#1B8E7D'],
  purple: ['#EDE4F7', '#6A4CA8'],
  indigo: ['#E8EAF6', '#4B5AA5'],
  orange: ['#FCE8DC', '#B65C2E'],
  pink: ['#FBE2EE', '#BE3D77'],
};

/* 第 8 周（10/20 周一 ~ 10/26 周日），今天是周三 */
const DAYS = [
  { l: '一', d: '10/20' },
  { l: '二', d: '10/21' },
  { l: '三', d: '10/22' },
  { l: '四', d: '10/23' },
  { l: '五', d: '10/24' },
  { l: '六', d: '10/25' },
  { l: '日', d: '10/26' },
];
const TODAY = 3;

const COURSES = [
  { d: 1, p: [1, 2], n: '高等数学', loc: 'J1-101', t: '张明', c: 'blue' },
  { d: 1, p: [3, 4], n: '大学英语', loc: 'J2-205', t: '李静', c: 'green' },
  { d: 1, p: [5, 6], n: '线性代数', loc: 'J1-203', t: '王强', c: 'yellow' },
  { d: 1, p: [9, 10], n: '体育', loc: '体育馆', t: '赵敏', c: 'orange' },
  { d: 2, p: [1, 2], n: '大学物理', loc: 'J3-302', t: '刘洋', c: 'cyan' },
  { d: 2, p: [3, 4], n: '程序设计基础', loc: 'J4-401', t: '陈晨', c: 'indigo' },
  { d: 2, p: [7, 8], n: '数据结构', loc: 'J1-105', t: '陈晨', c: 'purple' },
  { d: 3, p: [1, 2], n: '数据结构', loc: 'J1-105', t: '陈晨', c: 'purple' },
  { d: 3, p: [3, 4], n: '高等数学', loc: 'J1-101', t: '张明', c: 'blue' },
  { d: 3, p: [5, 6], n: '大学英语', loc: 'J2-205', t: '李静', c: 'green' },
  { d: 3, p: [9, 10], n: '大学物理', loc: 'J3-302', t: '刘洋', c: 'cyan' },
  { d: 4, p: [1, 2], n: '线性代数', loc: 'J1-203', t: '王强', c: 'yellow' },
  { d: 4, p: [3, 4], n: '程序设计基础', loc: 'J4-401', t: '陈晨', c: 'indigo' },
  { d: 4, p: [5, 6], n: '大学物理', loc: 'J3-302', t: '刘洋', c: 'cyan' },
  { d: 4, p: [7, 8], n: '数据结构', loc: 'J1-105', t: '陈晨', c: 'purple' },
  { d: 5, p: [3, 4], n: '高等数学', loc: 'J1-101', t: '张明', c: 'blue' },
  { d: 5, p: [5, 6], n: '数据结构', loc: 'J1-105', t: '陈晨', c: 'purple' },
  { d: 5, p: [7, 8], n: '大学英语', loc: 'J2-205', t: '李静', c: 'green' },
  { d: 6, p: [5, 6], n: '社团活动', loc: '活动中心', t: '', c: 'pink' },
];

const ICON = {
  chevDown:
    '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.6" stroke-linecap="round" stroke-linejoin="round"><path d="m6 9 6 6 6-6"/></svg>',
  refresh:
    '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 12a9 9 0 1 1-2.64-6.36"/><path d="M21 3v6h-6"/></svg>',
  clock:
    '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 7.5V12l3.2 2"/></svg>',
  plus:
    '<svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2.3" stroke-linecap="round"><path d="M12 5v14M5 12h14"/></svg>',
  search:
    '<svg width="15" height="15" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"><circle cx="11" cy="11" r="7"/><path d="m20 20-3.5-3.5"/></svg>',
  x:
    '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"><path d="M6 6l12 12M18 6 6 18"/></svg>',
  navGrid:
    '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linejoin="round"><rect x="3.5" y="3.5" width="7" height="7" rx="1.6"/><rect x="13.5" y="3.5" width="7" height="7" rx="1.6"/><rect x="3.5" y="13.5" width="7" height="7" rx="1.6"/><rect x="13.5" y="13.5" width="7" height="7" rx="1.6"/></svg>',
  navDoor:
    '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M13 4H6a1 1 0 0 0-1 1v15h8V4Z"/><path d="M13 4l5 1.2V20l-5 1"/><circle cx="9.6" cy="12.4" r=".9" fill="currentColor" stroke="none"/></svg>',
  navBook:
    '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><path d="M12 6.4C10.6 4.9 8.6 4.2 5.6 4.2c-.9 0-1.6.7-1.6 1.6v11c0 .9.7 1.6 1.6 1.6 3 0 5 .7 6.4 2.2 1.4-1.5 3.4-2.2 6.4-2.2.9 0 1.6-.7 1.6-1.6v-11c0-.9-.7-1.6-1.6-1.6-3 0-5 .7-6.4 2.2Z"/><path d="M12 6.4v14.2"/></svg>',
  navUser:
    '<svg width="22" height="22" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="8.2" r="3.6"/><path d="M4.8 20c.9-3.4 3.7-5.4 7.2-5.4s6.3 2 7.2 5.4"/></svg>',
  chevLeft:
    '<svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.1" stroke-linecap="round" stroke-linejoin="round"><path d="m14 6-6 6 6 6"/></svg>',
  info:
    '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="9"/><path d="M12 11v5.5"/><circle cx="12" cy="7.9" r="1.1" fill="currentColor" stroke="none"/></svg>',
  eye:
    '<svg width="16" height="16" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M2.5 12S6 5.8 12 5.8 21.5 12 21.5 12 18 18.2 12 18.2 2.5 12 2.5 12Z"/><circle cx="12" cy="12" r="3"/></svg>',
  check:
    '<svg width="14" height="14" viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="3" stroke-linecap="round" stroke-linejoin="round"><path d="m5 12.5 4.5 4.5L19 7"/></svg>',
};

const TABS = [
  { t: '课表', i: ICON.navGrid },
  { t: '教室状态', i: ICON.navDoor },
  { t: '选课', i: ICON.navBook },
  { t: '我的信息', i: ICON.navUser },
];

function statusBar(bg, fg) {
  const c = fg || '#1F2430';
  const bar = (h, o) =>
    `<rect x="${o}" y="${10 - h}" width="3" height="${h}" rx="1.2" fill="${c}"/>`;
  return `<div class="sbar" style="background:${bg};color:${c}">
    <span>9:41</span>
    <span class="sig">
      <svg width="18" height="12" viewBox="0 0 18 12">${bar(4, 0)}${bar(6.5, 4.6)}${bar(9, 9.2)}${bar(11.5, 13.8)}</svg>
      <svg width="16" height="12" viewBox="0 0 16 12" fill="${c}"><path d="M8 9.6a1.5 1.5 0 1 1 0 2.4 1.5 1.5 0 0 1 0-2.4Z"/><path d="M4.9 7.1a4.6 4.6 0 0 1 6.2 0l-1.3 1.4a2.8 2.8 0 0 0-3.6 0L4.9 7.1Z" opacity=".9"/><path d="M2.4 4.5a8.1 8.1 0 0 1 11.2 0l-1.3 1.4a6.2 6.2 0 0 0-8.6 0L2.4 4.5Z" opacity=".7"/></svg>
      <svg width="24" height="12" viewBox="0 0 24 12"><rect x=".6" y=".6" width="20" height="10.8" rx="3" fill="none" stroke="${c}" stroke-opacity=".4"/><rect x="2.2" y="2.2" width="15" height="7.6" rx="1.8" fill="${c}"/><path d="M22 4.2v3.6a2.2 2.2 0 0 0 0-3.6Z" fill="${c}" fill-opacity=".45"/></svg>
    </span>
  </div>`;
}

function header() {
  return `<div class="hdr">
    <span class="title">广应科课表</span>
    <span class="pill">第 8 周${ICON.chevDown}</span>
    <span class="grow"></span>
    <span class="act">${ICON.refresh}</span>
    <span class="act">${ICON.clock}</span>
  </div>`;
}

function weekStrip() {
  return `<div class="strip">
    <div class="gutter"></div>
    ${DAYS.map(
      (d, i) => `<div class="dcell${i + 1 === TODAY ? ' today' : ''}">
        <div class="daybox"><div class="a">${d.l}</div><div class="b">${d.d}</div></div>
      </div>`
    ).join('')}
  </div>`;
}

function grid(fab) {
  const gutter = PERIODS.map((p) => {
    const cell = `<div class="pcell"><div class="n">${p.n}</div><div class="t">${p.s}</div><div class="t">${p.e}</div></div>`;
    const brk = p.brk ? `<div class="brk">${p.brk}</div>` : '';
    return cell + brk;
  }).join('');

  const cols = DAYS.map((d, i) => {
    const cells = PERIODS.map(
      (p) => `<div class="pcell"></div>` + (p.brk ? `<div class="brk"></div>` : '')
    ).join('');
    const cards = COURSES.filter((c) => c.d === i + 1)
      .map((c) => {
        const [fill, accent] = PALETTE[c.c];
        const top = topOf(c.p[0]) + 2;
        const h = heightOf(c.p[0], c.p[1]) - 4;
        const teacher =
          c.p[1] - c.p[0] + 1 >= 2 && c.t ? `<div class="m">${c.t}</div>` : '';
        return `<div class="card" style="top:${top}px;height:${h}px;background:${fill};border-left-color:${accent};color:${accent}">
          <div class="n">${c.n}</div><div class="m">@${c.loc}</div>${teacher}
        </div>`;
      })
      .join('');
    return `<div class="daycol${i + 1 === TODAY ? ' is-today' : ''}">${cells}${cards}</div>`;
  }).join('');

  return `<div class="gwrap">
    <div class="grid"><div class="gut">${gutter}</div>${cols}</div>
    ${fab ? `<div class="fab">${ICON.plus}</div>` : ''}
  </div>`;
}

function nav(tab) {
  return `<div class="nav">${TABS.map(
    (t, i) =>
      `<div class="item${i === tab ? ' on' : ''}">${t.i}<span>${t.t}</span></div>`
  ).join('')}</div>`;
}

/** 课表主界面 */
function renderTimetable(el, opts) {
  const o = Object.assign({ tab: 0, fab: true }, opts || {});
  el.innerHTML =
    statusBar('#fff') + header() + weekStrip() + grid(o.fab) + nav(o.tab);
}

/** 课程详情：课表打底 + 居中液态玻璃卡 */
function renderCourseDetail(el) {
  renderTimetable(el, { tab: 0, fab: true });
  el.insertAdjacentHTML(
    'beforeend',
    `<div class="scrim"><div class="glass">
      <div class="row1">
        <span class="dot" style="background:#2C63D4"></span>
        <span class="kicker">课程详情</span><span style="flex:1"></span>
        <span style="color:#1F2430">${ICON.x}</span>
      </div>
      <div class="cname">高等数学</div>
      <div class="hcard">
        <div class="lab">上课时间</div>
        <div class="big">10:15 – 11:50</div>
        <div class="sub">周三 · 第 3-4 节</div>
        <div class="sep"></div>
        <div class="lab">上课地点</div>
        <div class="big">J1-101</div>
      </div>
      <div class="info"><span class="k">授课教师</span><span class="v">张明</span></div>
      <div class="info"><span class="k">上课周次</span><span class="v">1-16 周</span></div>
      <div class="info"><span class="k">课程属性</span><span class="v">必修</span></div>
      <div class="info"><span class="k">学分</span><span class="v">4</span></div>
      <div class="note">第 8 周正常上课</div>
    </div></div>`
  );
}

/** 登录教务系统页（验证码默认隐藏，点「登录」由本机离线识别并自动提交） */
function renderLogin(el) {
  const field = (label, value, hint, mono, suffix) => `
    <div class="lfield">
      <div class="lb">${label}</div>
      <div class="lv${mono ? ' mono' : ''}">${value || `<span class="ph">${hint}</span>`}${suffix || ''}</div>
    </div>`;

  el.innerHTML = `
    ${statusBar('#fff')}
    <div class="hdr">
      <span class="act" style="margin-left:-8px">${ICON.chevLeft}</span>
      <span class="title" style="font-size:17px;font-weight:600;margin-left:2px">登录教务系统</span>
    </div>
    <div class="lbody">
      <div class="lhint">
        <span style="color:#2C63D4;flex:none">${ICON.info}</span>
        <span>会话过期后，在这里用学号密码重新登录即可。登录成功后会话与学号保存在本机，下次打开不用再登；勾选「记住密码」可以把密码也存在本机（下次登录免输）。<b>验证码不用你管</b>：点「登录」后由本机离线识别并自动提交，偶尔认错会自动换一张重试；实在识别不出来时验证码框会自己出现，照图输入即可。随时可在「我的信息」页退出登录。</span>
      </div>
      ${field('学号 / 账号', '2023180102')}
      ${field('密码', '••••••••', '', true, `<span style="color:#8A8F9C">${ICON.eye}</span>`)}
      <div class="lcheck">
        <span class="box check">${ICON.check}</span>
        <span class="lb2">记住密码</span>
        <span class="lb3">仅保存在本机，只为下次免输</span>
      </div>
      <div class="lbtn">登录</div>
    </div>`;
}
function renderClassroom(el) {
  const rooms = [
    { n: 'J1-101', ex: '座位 60 · 多媒体', busy: [1, 1, 0, 0, 0, 1, 1, 0, 0, 0, 0] },
    { n: 'J1-102', ex: '座位 60 · 多媒体', busy: [1, 1, 1, 0, 0, 0, 1, 0, 0, 0, 0] },
    { n: 'J1-201', ex: '座位 90 · 多媒体', busy: [0, 0, 1, 1, 1, 1, 0, 0, 0, 0, 0] },
    { n: 'J1-202', ex: '座位 90 · 多媒体', busy: [0, 0, 0, 0, 0, 0, 1, 1, 1, 0, 0] },
    { n: 'J1-301', ex: '座位 120 · 智慧教室', busy: [1, 0, 0, 1, 1, 0, 0, 0, 0, 0, 0] },
    { n: 'J1-302', ex: '座位 120 · 智慧教室', busy: [0, 1, 1, 0, 0, 1, 1, 1, 0, 1, 0] },
  ];
  const bars = (busy) => {
    const groups = [busy.slice(0, 4), busy.slice(4, 8), busy.slice(8, 11)];
    return groups
      .map(
        (g) =>
          `<div class="grp">${g
            .map((b) => `<div class="b ${b ? 'b-busy' : 'b-free'}"></div>`)
            .join('')}</div>`
      )
      .join('');
  };

  el.innerHTML = `
    ${statusBar('#3A5AA6', '#fff')}
    <div class="roomhdr">
      <h1>教室状态</h1>
      <div class="chips">
        <span class="chip on">肇庆校区</span><span class="chip">广州校区</span>
      </div>
      <div class="chips scroll">
        <span class="chip on">J1 教学楼</span><span class="chip">J2 教学楼</span>
        <span class="chip">实验楼</span><span class="chip">图书馆</span>
      </div>
      <div class="chips dates">
        <span class="chip on">今天</span><span class="chip">10/23</span><span class="chip">10/24</span>
        <span class="chip">10/25</span><span class="chip">10/26</span><span class="chip">10/27</span>
      </div>
    </div>
    <div class="roombody">
      <div class="search">${ICON.search}<span>搜索教室，如 J1-101</span></div>
      <div class="sum">共 24 间教室 · 全天空闲 6 间</div>
      <div class="legend">
        <span class="lgdot" style="background:#7CC47F"></span>空闲
        <span class="lgdot" style="background:#E2636B;margin-left:14px"></span>占用
        <span class="grow"></span>
        <span class="gt" style="width:47px">上午</span>
        <span class="gt" style="width:47px;margin-left:10px">下午</span>
        <span class="gt" style="width:37px;margin-left:10px">晚上</span>
      </div>
      <div class="roomlist">
        ${rooms
          .map(
            (r) => `<div class="room">
              <div class="info-col"><div class="nm">${r.n}</div><div class="ex">${r.ex}</div></div>
              <div class="bars">${bars(r.busy)}</div>
            </div>`
          )
          .join('')}
      </div>
    </div>
    ${nav(1)}`;
}
