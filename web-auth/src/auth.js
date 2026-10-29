import Keycloak from 'keycloak-js';

let client;
let admin = false;

window.esmaAuthInit = async () => {
  const config = window.ESMA_OIDC_CONFIG || {};
  if (!config.url || !config.realm || !config.clientId) return false;
  client = new Keycloak({ url: config.url, realm: config.realm, clientId: config.clientId });
  const authenticated = await client.init({
    onLoad: 'check-sso',
    pkceMethod: 'S256',
    checkLoginIframe: false,
    silentCheckSsoRedirectUri: `${window.location.origin}/silent-check-sso.html`,
    silentCheckSsoFallback: false,
  });
  admin = Boolean(authenticated && client.tokenParsed?.realm_access?.roles?.includes('admin'));
  return admin;
};

window.esmaAuthToken = async () => {
  if (!client?.authenticated) return '';
  try { await client.updateToken(30); return client.token || ''; }
  catch { admin = false; return ''; }
};

window.esmaAuthUsername = () => client?.tokenParsed?.name || client?.tokenParsed?.preferred_username || 'Admin';
window.esmaAuthLogin = () => client?.login({ redirectUri: `${window.location.origin}/admin` });
window.esmaAuthLogout = () => client?.logout({ redirectUri: window.location.origin });
