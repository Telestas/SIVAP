import { proxyFirestore } from '../_lib/proxyFirebase.js';

export const onRequest = ({ request }) => proxyFirestore(request);
