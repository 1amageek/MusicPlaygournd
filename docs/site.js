const copy = document.getElementById('copy');
const status = document.getElementById('copy-status');
copy.hidden = false;
copy.addEventListener('click', async () => {
  try {
    if (!navigator.clipboard) throw new Error('Clipboard unavailable');
    await navigator.clipboard.writeText(document.getElementById('commands').textContent);
    status.textContent = 'Commands copied.';
  } catch {
    status.textContent = 'Copy is unavailable here. Select and copy the commands above.';
  }
});
