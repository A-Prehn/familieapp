// ---------------------------------------------------------------------------
// Datalag — swapbart bag ét interface. Prototype: LocalStore (localStorage).
// Fase 2: CloudKitStore med samme metoder (privat DB + CKShare + CKAsset).
//
// Multi-tenant og publicerings-klar: alt hænger på en FAMILIE-enhed, ikke på
// én hardcodet familie. En familie ejer børn OG fælles indhold (begivenheder,
// ferier, fødselsdage). Deling sker på familie-niveau → begge forældre ser alt.
//
// Datamodel:
//   User   { id, name }
//   Family { id, name, ownerId, memberIds[], events[], vacations[], birthdays[] }
//   Child  { id, familyId, name, birthDate, dueDate, gender, createdAt,
//            milestones{}, aboutMe{}, highlights[], diary[], bellyGallery[], monthlyGallery[] }
// Fotos gemmes som dataURL (≈ CKAsset).
// ---------------------------------------------------------------------------

const KEY = "familieapp.v2";
const uid = () => Math.random().toString(36).slice(2, 10) + Date.now().toString(36);
const delay = (ms = 80) => new Promise((r) => setTimeout(r, ms));

function load() {
  try {
    return JSON.parse(localStorage.getItem(KEY)) || { users: {}, families: {}, children: {}, invites: {} };
  } catch {
    return { users: {}, families: {}, children: {}, invites: {} };
  }
}
function save(db) {
  localStorage.setItem(KEY, JSON.stringify(db));
  window.dispatchEvent(new Event("familieapp:changed"));
}

function newChild(familyId, { name, birthDate, dueDate, gender }) {
  return {
    id: "child_" + uid(),
    familyId,
    name: (name || "").trim(),
    birthDate: birthDate || null,
    dueDate: dueDate || null,
    gender: gender || "unspecified",
    createdAt: Date.now(),
    milestones: {},
    aboutMe: {},
    highlights: [],
    diary: [],
    bellyGallery: [],
    monthlyGallery: [],
  };
}

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

  // --- Familie -------------------------------------------------------------
  async createFamily(userId, name) {
    const db = load();
    const id = "family_" + uid();
    db.families[id] = {
      id,
      name: name?.trim() || "Vores familie",
      ownerId: userId,
      memberIds: [userId],
      events: [],
      vacations: [],
      birthdays: [],
    };
    save(db);
    await delay();
    return db.families[id];
  }
  async listFamilies(userId) {
    await delay();
    const db = load();
    return Object.values(db.families).filter((f) => f.memberIds.includes(userId));
  }
  async getFamily(id) {
    return load().families[id] || null;
  }
  async updateFamily(id, patch) {
    const db = load();
    const f = db.families[id];
    if (!f) throw new Error("Familie findes ikke.");
    Object.assign(f, patch);
    save(db);
    return f;
  }
  async listMembers(familyId) {
    const db = load();
    const f = db.families[familyId];
    if (!f) return [];
    return f.memberIds.map((id) => db.users[id]).filter(Boolean);
  }

  // Fælles indhold — tilføj til array på familien.
  async addFamilyItem(familyId, collection, item) {
    const db = load();
    const f = db.families[familyId];
    if (!f[collection]) f[collection] = [];
    const full = { id: uid(), createdAt: Date.now(), ...item };
    f[collection].push(full);
    save(db);
    await delay();
    return full;
  }

  // --- Børn ----------------------------------------------------------------
  async createChild(familyId, data) {
    const db = load();
    const child = newChild(familyId, data);
    db.children[child.id] = child;
    save(db);
    await delay();
    return child;
  }
  async listChildren(familyId) {
    await delay();
    const db = load();
    return Object.values(db.children)
      .filter((c) => c.familyId === familyId)
      .sort((a, b) => a.createdAt - b.createdAt);
  }
  async getChild(id) {
    return load().children[id] || null;
  }
  async updateChild(id, patch) {
    const db = load();
    const c = db.children[id];
    if (!c) throw new Error("Barn findes ikke.");
    Object.assign(c, patch);
    save(db);
    return c;
  }

  // Sæt felt i et nested objekt på barnet (milestones / aboutMe).
  async setChildField(childId, objectKey, field, value) {
    const db = load();
    const c = db.children[childId];
    if (!c[objectKey]) c[objectKey] = {};
    if (value === null || value === "" || value === undefined) delete c[objectKey][field];
    else c[objectKey][field] = value;
    save(db);
    return c;
  }

  // Tilføj til et array på barnet (highlights / diary / bellyGallery / monthlyGallery).
  async addChildItem(childId, collection, item) {
    const db = load();
    const c = db.children[childId];
    if (!c[collection]) c[collection] = [];
    const full = { id: uid(), createdAt: Date.now(), ...item };
    c[collection].push(full);
    save(db);
    await delay();
    return full;
  }

  // --- Deling (CKShare-ækvivalent, hele familien) --------------------------
  async createInvite(userId, familyId) {
    const db = load();
    const code = uid().slice(0, 6).toUpperCase();
    db.invites[code] = { code, familyId, invitedBy: userId, createdAt: Date.now() };
    save(db);
    return code;
  }
  async acceptInvite(userId, code) {
    const db = load();
    const invite = db.invites[code?.trim().toUpperCase()];
    if (!invite) throw new Error("Ugyldig invitationskode.");
    const f = db.families[invite.familyId];
    if (!f) throw new Error("Familien findes ikke længere.");
    if (!f.memberIds.includes(userId)) f.memberIds.push(userId);
    save(db);
    await delay();
    return f;
  }
}

export const store = new LocalStore();
