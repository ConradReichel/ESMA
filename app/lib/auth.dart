import 'dart:js_interop';

@JS('esmaAuthInit')
external JSPromise<JSBoolean> _authInit();
@JS('esmaAuthToken')
external JSPromise<JSString> _authToken();
@JS('esmaAuthUsername')
external JSString _authUsername();
@JS('esmaAuthLogin')
external JSPromise<JSAny?> _authLogin();
@JS('esmaAuthLogout')
external JSPromise<JSAny?> _authLogout();

Future<bool> initAuth() async => (await _authInit().toDart).toDart;
Future<String> authToken() async => (await _authToken().toDart).toDart;
String authUsername() => _authUsername().toDart;
void authLogin() { _authLogin(); }
void authLogout() { _authLogout(); }
