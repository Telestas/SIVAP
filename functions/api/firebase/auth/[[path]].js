import { proxyIdentidad } from '../../../_lib/proxyFirebase.js';

export const onRequest = ({ request }) => proxyIdentidad(request, 'auth');
