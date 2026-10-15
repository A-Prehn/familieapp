// ---------------------------------------------------------------------------
// Datalag — swapbart bag ét interface.
//
// Prototypen bruger LocalStore (localStorage). Når appen bygges i SwiftUI,
// erstattes dette lag af en CloudKitStore med SAMME metoder, så UI-laget
// ikke behøver ændres. Alle metoder er async (Promise-baserede), fordi
// CloudKit-kald også er det.
//
// VIGTIGT: Intet her er familiespecifikt. Alt data hører til den indloggede
// bruger (ownerId/memberIds). Appen er multi-tenant og kan deles.
// ---------------------------------------------------------------------------

const KEY = "familieapp.v1";
const uid = () => Math.random().toString(36).slice(2, 10) + Date.now().toString(36);

function load() {
  try {
    return JSON.parse(localStorage.getItem(KEY)) || { users: {}, children: {}, posts: {}, invites: {} };
  } catch {
    return { users: {}, children: {}, posts: {}, invites: {} };
  }
}

function save(db) {
  localStorage.setItem(KEY, JSON.stringify(db));
  // Signalér ændring til andre faner/komponenter (simulerer realtids-sync).
  window.dispatchEvent(new Event("familieapp:changed"));
}

const delay = (ms = 120) => new Promise((r) => setTimeout(r, ms));

export class LocalStore {
  // --- Auth (mock Sign in with Apple) --------------------------------------
  async signIn(name) {
    const db = load();
    const id = "user_" + uid();
    db.users[id] = { id, name: name?.trim() || "Forælder" };
    save(db);
    return db.users[id];
  }

  async getUser(id) {
    return load().users[id] || null;
  }

  // --- Børn ----------------------------------------------------------------
  async createChild(userId, { name, birthDate, gender }) {
    const db = load();
    const id = "child_" + uid();
    db.children[id] = {
      id,
      name: name.trim(),
      birthDate: birthDate || null,
      gender: gender || "unspecified",
      ownerId: userId,
      memberIds: [userId],
      createdAt: Date.now(),
    };
    save(db);
    await delay();
    return db.children[id];
  }

  async listChildren(userId) {
    await delay();
    const db = load();
    return Object.values(db.children)
      .filter((c) => c.memberIds.includes(userId))
      .sort((a, b) => a.createdAt - b.createdAt);
  }

  async getChild(childId) {
    return load().children[childId] || null;
  }

  // --- Opslag (med foto som dataURL ~ CKAsset) -----------------------------
  async createPost(userId, childId, { text, photo }) {
    const db = load();
    const user = db.users[userId];
    const id = "post_" + uid();
    db.posts[id] = {
      id,
      childId,
      authorId: userId,
      authorName: user?.name || "Ukendt",
      text: text?.trim() || "",
      photo: photo || null,
      createdAt: Date.now(),
    };
    save(db);
    await delay();
    return db.posts[id];
  }

  async listPosts(childId) {
    await delay();
    const db = load();
    return Object.values(db.posts)
      .filter((p) => p.childId === childId)
      .sort((a, b) => b.createdAt - a.createdAt);
  }

  // --- Deling (CKShare-ækvivalent) -----------------------------------------
  async createInvite(userId, childId) {
    const db = load();
    const code = uid().slice(0, 6).toUpperCase();
    db.invites[code] = { code, childId, invitedBy: userId, createdAt: Date.now() };
    save(db);
    return code;
  }

  async acceptInvite(userId, code) {
    const db = load();
    const invite = db.invites[code?.trim().toUpperCase()];
    if (!invite) throw new Error("Ugyldig invitationskode.");
    const child = db.children[invite.childId];
    if (!child) throw new Error("Barnet findes ikke længere.");
    if (!child.memberIds.includes(userId)) child.memberIds.push(userId);
    save(db);
    await delay();
    return child;
  }

  async listMembers(childId) {
    const db = load();
    const child = db.children[childId];
    if (!child) return [];
    return child.memberIds.map((id) => db.users[id]).filter(Boolean);
  }
}

export const store = new LocalStore();
