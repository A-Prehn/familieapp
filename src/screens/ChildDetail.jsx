import { useApp, useLiveData } from "../lib/AppContext";

function when(ts) {
  const d = new Date(ts);
  return d.toLocaleDateString("da-DK", { day: "numeric", month: "short", year: "numeric" });
}

export default function ChildDetail({ nav, childId }) {
  const { store } = useApp();
  const { data: child } = useLiveData(() => store.getChild(childId), [childId]);
  const { data: posts } = useLiveData(() => store.listPosts(childId), [childId]);
  const { data: members } = useLiveData(() => store.listMembers(childId), [childId]);

  if (!child) return null;

  return (
    <>
      <div className="nav">
        <button className="back" onClick={nav.pop}>‹ Hjem</button>
        <div className="title">{child.name}</div>
        <button className="action" onClick={() => nav.push("share", { childId })}>Del</button>
      </div>

      <div className="content">
        {members && members.length > 1 && (
          <div style={{ marginBottom: 12 }}>
            {members.map((m) => (
              <span key={m.id} className="member-pill">👤 {m.name}</span>
            ))}
          </div>
        )}

        {posts == null ? null : posts.length === 0 ? (
          <div className="empty">
            <span className="emoji">📷</span>
            Ingen opslag endnu.<br />Læg det første øjeblik op.
          </div>
        ) : (
          posts.map((p) => (
            <div key={p.id} className="card post">
              {p.photo && <img src={p.photo} alt="" />}
              <div className="post-body">
                <div className="post-meta">
                  <span>{p.authorName}</span>
                  <span>{when(p.createdAt)}</span>
                </div>
                {p.text && <div className="post-text">{p.text}</div>}
              </div>
            </div>
          ))
        )}

        <button className="btn" onClick={() => nav.push("newPost", { childId })} style={{ marginTop: 8 }}>
          ＋ Nyt opslag
        </button>
      </div>
    </>
  );
}
