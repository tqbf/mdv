# Diff Tinting

Fenced `diff` and `patch` blocks colour added and removed lines with the
theme's diff palette. Flip themes to compare; the `+` / `-` column should
always stay visible.

## A git diff

Two files, a hunk-count edge case, and a missing trailing newline. The
removed line `-- stale comment` shows as `--- stale comment` and must be
tinted as a removal, not bolded as a file header.

```diff
diff --git a/schema.sql b/schema.sql
index 3b18e51..a4c2d09 100644
--- a/schema.sql
+++ b/schema.sql
@@ -1,6 +1,6 @@
 CREATE TABLE notes (
     id INTEGER PRIMARY KEY,
--- stale comment
+    -- body is markdown
     body TEXT NOT NULL,
-    created TEXT
+    created TEXT NOT NULL DEFAULT (datetime('now'))
 );
diff --git a/notes.txt b/notes.txt
new file mode 100644
index 0000000..e69de29
--- /dev/null
+++ b/notes.txt
@@ -0,0 +1 @@
+remember the milk
\ No newline at end of file
```

## A hand-written snippet

No file or hunk headers, as diffs usually appear in prose.

```diff
 func greet(name string) string {
-    return "Hello, " + name
+    return fmt.Sprintf("Hello, %s!", name)
 }
```

## The `patch` alias

```patch
--- a/README
+++ b/README
@@ -1 +1,2 @@
 mdv
+A native markdown viewer.
```
