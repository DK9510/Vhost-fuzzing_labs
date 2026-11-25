/* Chat Admin bundle — lab C07 */
window.__ENV = {
  API_BASE: "https://api.portal.corp.lab/api",
  RESET: "/api/auth/password_reset/confirm"
};
document.getElementById("reset")?.addEventListener("submit", function (ev) {
  ev.preventDefault();
  var f = ev.target;
  fetch(window.__ENV.API_BASE + "/auth/password_reset/confirm", {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify({ token: f.token.value, password: f.password.value })
  }).then(function (r) { return r.json(); }).then(alert);
});
