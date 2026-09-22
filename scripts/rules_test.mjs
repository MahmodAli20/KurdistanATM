// Exercises the deployed Firestore rules as a real anonymous client.
// Confirms the app's own write path works AND that the abuse paths are refused.
//
// Run after any change to firestore.rules:
//     npm install && node rules_test.mjs
//
// This writes to the LIVE database, using the machine id `testatm00001` which
// is deliberately absent from the bundled dataset, so the app never displays
// it. The rules forbid removing machines from a city and forbid touching the
// audit log at all, so the script cannot tidy up after itself. Clear it with
// admin credentials:
//
//     firebase firestore:delete "status/erbil" --recursive --force \
//       --project=atm-finder-4406e
//     firebase firestore:delete "reports" --recursive --force \
//       --project=atm-finder-4406e
//
// Expect PERMISSION_DENIED noise on stderr - those are the denials being
// logged by the gRPC layer, and they are the test passing, not failing.
import { initializeApp } from 'firebase/app';
import { getAuth, signInAnonymously } from 'firebase/auth';
import {
  getFirestore, doc, getDoc, setDoc, addDoc, collection,
  serverTimestamp, runTransaction, deleteDoc, updateDoc,
} from 'firebase/firestore';

const app = initializeApp({
  apiKey: 'AIzaSyBeuwPmGKpi6GrV-yan0wTglR7k_QgNI0w',
  appId: '1:40647075508:web:f2c2078e38d83b2071d9e1',
  projectId: 'atm-finder-4406e',
  authDomain: 'atm-finder-4406e.firebaseapp.com',
  messagingSenderId: '40647075508',
});
const auth = getAuth(app);
const db = getFirestore(app);

let pass = 0, fail = 0;
async function expect(name, shouldSucceed, fn) {
  try {
    await fn();
    if (shouldSucceed) { console.log(`  PASS  ${name}`); pass++; }
    else { console.log(`  FAIL  ${name} -- was allowed but should be denied`); fail++; }
  } catch (e) {
    if (!shouldSucceed) { console.log(`  PASS  ${name} (denied)`); pass++; }
    else { console.log(`  FAIL  ${name} -- ${e.code || e.message}`); fail++; }
  }
}

const cred = await signInAnonymously(auth);
const uid = cred.user.uid;
console.log(`signed in anonymously as ${uid.slice(0, 8)}...\n`);

const CITY = 'erbil';
const ATM = 'testatm00001';
const cityRef = doc(db, 'status', CITY);

console.log('-- the app\'s real write path --');
await expect('transactional report into status/erbil', true, () =>
  runTransaction(db, async (tx) => {
    const snap = await tx.get(cityRef);
    const atms = { ...(snap.data()?.atms ?? {}) };
    const list = [...(atms[ATM] ?? [])];
    list.push({ s: 'hasCash', t: Date.now(), u: uid });
    atms[ATM] = list.slice(0, 12);
    tx.set(cityRef, { atms, updatedAt: serverTimestamp() }, { merge: true });
  }));

await expect('append to immutable reports log', true, () =>
  addDoc(collection(db, 'reports'), {
    atmId: ATM, city: CITY, status: 'hasCash', uid, createdAt: serverTimestamp(),
  }));

await expect('anyone can read city status', true, async () => {
  const snap = await getDoc(cityRef);
  if (!snap.exists()) throw new Error('missing');
});

console.log('\n-- abuse paths that must be refused --');

await expect('invented status value', false, () =>
  addDoc(collection(db, 'reports'), {
    atmId: ATM, city: CITY, status: 'freeMoney', uid, createdAt: serverTimestamp(),
  }));

await expect('unknown city', false, () =>
  addDoc(collection(db, 'reports'), {
    atmId: ATM, city: 'atlantis', status: 'hasCash', uid, createdAt: serverTimestamp(),
  }));

await expect('client-chosen timestamp instead of server time', false, () =>
  addDoc(collection(db, 'reports'), {
    atmId: ATM, city: CITY, status: 'hasCash', uid,
    createdAt: new Date('2030-01-01'),
  }));

await expect('report attributed to another uid', false, () =>
  addDoc(collection(db, 'reports'), {
    atmId: ATM, city: CITY, status: 'hasCash', uid: 'someone-else',
    createdAt: serverTimestamp(),
  }));

await expect('smuggling an extra field into a report', false, () =>
  addDoc(collection(db, 'reports'), {
    atmId: ATM, city: CITY, status: 'hasCash', uid,
    createdAt: serverTimestamp(), admin: true,
  }));

await expect('reading other people\'s reporting history', false, async () => {
  const { getDocs, query, limit } = await import('firebase/firestore');
  const snap = await getDocs(query(collection(db, 'reports'), limit(1)));
  if (snap.empty) throw new Error('empty');
});

await expect('wiping a whole city', false, () =>
  setDoc(cityRef, { atms: {}, updatedAt: serverTimestamp() }));

await expect('deleting a city document', false, () => deleteDoc(cityRef));

await expect('backdating the city document', false, () =>
  updateDoc(cityRef, { updatedAt: new Date('2020-01-01') }));

await expect('adding a rogue field to a city document', false, () =>
  updateDoc(cityRef, { owner: 'me', updatedAt: serverTimestamp() }));

await expect('writing to an unrelated collection', false, () =>
  addDoc(collection(db, 'secrets'), { x: 1 }));

console.log(`\n${pass} passed, ${fail} failed`);
process.exit(fail === 0 ? 0 : 1);
