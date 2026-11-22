const exchange = document.querySelector('#exchange');
const content = document.querySelector('#content');
const notice = document.querySelector('#notice');
const tabs = [...document.querySelectorAll('[data-tab]')];
let state = null;
let tab = 'open';
let wantsAdmin = false;
let waiting = false;
let timeout;

const asList = value => Array.isArray(value) ? value : [];
const money = cents => new Intl.NumberFormat('en-US', {
  style: 'currency', currency: 'USD',
}).format(cents / 100);
const date = seconds => new Date(seconds * 1000).toLocaleString([], {
  dateStyle: 'medium', timeStyle: 'short',
});

function node(tag, value, style) {
  const element = document.createElement(tag);
  if (value != null) element.textContent = value;
  if (style) element.className = style;
  return element;
}

function showNotice(message) {
  notice.textContent = message || '';
  notice.hidden = !message;
}

function post(route, data = {}) {
  return fetch('https://' + GetParentResourceName() + '/' + route, {
    method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(data),
  });
}

function setWaiting(value) {
  waiting = value;
  document.querySelectorAll('#content button, #refresh').forEach(button => {
    button.disabled = value;
  });
}

function request(action, fields = {}) {
  if (waiting) return;
  setWaiting(true);
  showNotice('');
  timeout = setTimeout(() => {
    setWaiting(false);
    showNotice('The server has not responded. Refresh to check your market and cash before retrying.');
  }, 8000);
  post('request', { action, ...fields }).catch(() => {
    clearTimeout(timeout);
    setWaiting(false);
    showNotice('Connection failed. Refresh to check your market and cash.');
  });
}

function button(label, handler, style) {
  const element = node('button', label, style);
  element.type = 'button';
  element.onclick = handler;
  return element;
}

function outcomeSelect(options) {
  const select = node('select');
  select.setAttribute('aria-label', 'Outcome');
  options.forEach((label, index) => {
    const choice = node('option', label);
    choice.value = index + 1;
    select.append(choice);
  });
  return select;
}

function arm(button, label, action) {
  button.onclick = () => {
    button.textContent = label;
    button.onclick = action;
  };
}

function card(market) {
  const root = node('article', null, 'card');
  const { id, options, totals, position, claim } = market;
  const total = totals[0] + totals[1];
  const share = total ? Math.round(100 * totals[0] / total) : 50;
  const label = market.status === 'refunded' ? 'Refunded'
    : market.winner ? 'Won by ' + options[market.winner - 1] : market.status;
  const metadata = node('div', null, 'market-meta');
  metadata.append(node('span', label, 'badge'), node('p', 'Pool ' + money(total), 'meta'));
  const closeLabel = market.status === 'open' ? 'Closes ' + date(market.closes) : 'Wagering ended';
  root.append(metadata, node('h2', market.title), node('p', closeLabel, 'meta'),
    node('p', market.rules, 'rules'));

  const bar = node('div', null, 'bar');
  bar.setAttribute('aria-hidden', 'true');
  const fill = node('span');
  fill.style.width = share + '%';
  bar.append(fill);
  const split = node('div', null, 'split');
  split.append(...options.map((name, index) => node('span', name + (total ? ' · ' + (index ? 100 - share : share) + '%' : ''))));
  root.append(split);
  if (total) root.append(bar);
  if (position[0] || position[1]) {
    const bets = options.map((name, index) => name + ' ' + money(position[index]));
    root.append(node('p', 'Your wagers · ' + bets.join(' / '), 'meta'));
  }

  const actions = node('form', null, 'actions');
  actions.onsubmit = event => event.preventDefault();
  if (tab === 'admin') {
    if (market.status === 'open') actions.append(button('Close now', event => request('close', { id })));
    if (market.status === 'closed') {
      const side = outcomeSelect(options);
      const settle = button('Settle market', null, 'primary');
      const reset = () => arm(settle, 'Confirm ' + options[Number(side.value) - 1],
        () => request('settle', { id, side: Number(side.value) }));
      side.onchange = () => { settle.textContent = 'Settle market'; reset(); };
      reset();
      actions.append(side, settle);
    }
    if (market.status === 'open' || market.status === 'closed') {
      const refund = button('Refund market');
      arm(refund, 'Confirm refund', () => request('refund', { id }));
      actions.append(refund);
    }
  } else if (claim && !state.pending) {
    actions.append(button('Claim ' + money(claim), () => request('claim', { id }), 'primary'));
  } else if (market.status === 'open' && !state.pending) {
    const side = outcomeSelect(options);
    const amount = node('input');
    amount.type = 'number';
    amount.required = true;
    amount.min = state.min;
    amount.max = state.max;
    amount.step = 1;
    amount.placeholder = '$ Cash';
    amount.setAttribute('aria-label', 'Wager in whole dollars');
    const submit = button('Place wager', null, 'primary');
    submit.type = 'submit';
    actions.onsubmit = event => {
      event.preventDefault();
      request('bet', { id, side: Number(side.value), amount: amount.valueAsNumber });
    };
    actions.append(side, amount, submit);
  }
  if (actions.children.length) root.append(actions);
  return root;
}

function createForm() {
  const form = node('form', null, 'card form admin-section');
  const field = (label, tag, attributes) => {
    const wrapper = node('label', label);
    const input = node(tag);
    Object.assign(input, { required: true }, attributes);
    wrapper.append(input);
    return wrapper;
  };
  const row = node('div', null, 'grid');
  row.append(field('First outcome', 'input', { name: 'first', value: 'Yes', maxLength: 40 }),
    field('Second outcome', 'input', { name: 'second', value: 'No', maxLength: 40 }),
    field('Minutes until close', 'input', { name: 'minutes', type: 'number', min: 1, max: 43200, value: 60 }));
  const publish = button('Publish market', null, 'primary');
  publish.type = 'submit';
  form.append(node('h2', 'Create a market'), field('Market question', 'input', {
    name: 'title', placeholder: 'Will the Marshals win Saturday’s race?', maxLength: 120,
  }), field('Resolution rules', 'textarea', { name: 'rules', rows: 2, maxLength: 800 }),
  row, publish);
  form.onsubmit = event => {
    event.preventDefault();
    const values = Object.fromEntries(new FormData(form));
    request('create', { ...values, minutes: Number(values.minutes) });
  };
  return form;
}

function reviewCard(review) {
  const root = node('article', null, 'card');
  root.append(node('h2', 'Cash review · Market #' + review.market),
    node('p', review.name + ' · ' + review.kind + ' · ' + date(review.time)),
    node('p', 'Character ' + review.key + ' · Before ' + money(review.before) + ' · Expected ' + money(review.after), 'meta'));
  const actions = node('div', null, 'actions');
  for (const applied of [true, false]) {
    const label = applied ? 'Cash moved' : 'Cash did not move';
    const choice = button(label);
    arm(choice, 'Confirm: ' + label, () => request('review', { key: review.key, applied }));
    actions.append(choice);
  }
  root.append(actions);
  return root;
}

function render() {
  document.querySelector('#cash').textContent = Number.isFinite(state?.balance) ? money(state.balance) : '—';
  tabs.forEach(button => {
    button.hidden = button.dataset.tab === 'admin' && !state?.admin;
    if (button.dataset.tab === tab) button.setAttribute('aria-current', 'page');
    else button.removeAttribute('aria-current');
  });
  content.replaceChildren();
  if (!state) {
    content.append(node('p', waiting ? 'Loading markets…' : 'Refresh to load markets.', 'meta'));
    return;
  }
  if (state.pending) content.append(node('p', 'Your character has a cash movement awaiting staff review.', 'badge'));
  if (tab === 'admin') {
    content.append(createForm());
    const reviews = asList(state.reviews);
    if (reviews.length) {
      const reviewSection = node('section', null, 'admin-section');
      const reviewGrid = node('div', null, 'grid');
      reviewGrid.append(...reviews.map(reviewCard));
      reviewSection.append(node('h2', 'Pending cash reviews'), reviewGrid);
      content.append(reviewSection);
    }
    content.append(node('h2', 'Active markets'));
  }
  const markets = asList(state.markets).filter(m => {
    if (tab === 'admin') return m.status === 'open' || m.status === 'closed';
    return tab === 'open' ? m.status === 'open' : m.status !== 'open';
  });
  const grid = node('div', null, 'grid');
  grid.append(...markets.map(card));
  content.append(markets.length ? grid : node('p', tab === 'history' ? 'No results or claims yet.' : 'No markets in this view.', 'meta empty'));
  setWaiting(waiting);
}

tabs.forEach(button => {
  button.onclick = () => {
    tab = button.dataset.tab;
    render();
  };
});
document.querySelector('#refresh').onclick = () => request('view');

function close() {
  document.body.hidden = true;
  exchange.hidden = true;
  state = null;
  clearTimeout(timeout);
  post('close').catch(() => {});
}
document.querySelector('#exit').onclick = close;
window.addEventListener('keydown', event => {
  if (event.key === 'Escape' && !exchange.hidden) close();
});
window.addEventListener('message', ({ data }) => {
  if (data.type === 'close') {
    document.body.hidden = true;
    exchange.hidden = true;
  }
  if (data.type === 'open') {
    clearTimeout(timeout);
    waiting = false;
    wantsAdmin = data.admin;
    state = null;
    tab = 'open';
    document.querySelector('#brand').textContent = data.brand;
    exchange.hidden = false;
    document.body.hidden = false;
    request('view');
    render();
  }
  if (data.type === 'response' && !exchange.hidden) {
    clearTimeout(timeout);
    setWaiting(false);
    if ('markets' in data) {
      state = data;
      if (wantsAdmin && data.admin) tab = 'admin';
      if (tab === 'admin' && !data.admin) tab = 'open';
      render();
    }
    showNotice(data.error || data.notice || (wantsAdmin && state && !state.admin ? 'Staff access required.' : ''));
    wantsAdmin = false;
  }
});
