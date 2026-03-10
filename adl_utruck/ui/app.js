const remote = document.getElementById('remote');
const buttonsLayer = document.getElementById('buttons-layer');

const buttons = {
  up: document.getElementById('btn-up'),
  down: document.getElementById('btn-down'),
  west: document.getElementById('btn-west'),
  east: document.getElementById('btn-east')
};

function setVisible(visible) {
  remote.classList.toggle('hidden', !visible);
  remote.setAttribute('aria-hidden', String(!visible));
}

function setState(state) {
  for (const key of Object.keys(buttons)) {
    buttons[key].classList.toggle('active', Boolean(state[key]));
    buttonsLayer.classList.toggle(key, Boolean(state[key]));
  }

  const moving = Object.keys(buttons).some((key) => Boolean(state[key]));
  buttonsLayer.classList.toggle('moving', moving);
}

window.addEventListener('message', (event) => {
  const data = event.data || {};

  if (data.action === 'setVisible') {
    setVisible(Boolean(data.visible));
    return;
  }

  if (data.action === 'setState') {
    setState(data);
  }
});
