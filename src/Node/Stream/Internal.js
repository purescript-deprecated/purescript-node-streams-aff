export function onceReadable(s) {
  return f => () => {
    s.once("readable", f);
  };
}