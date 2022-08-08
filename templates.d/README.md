# Templates for things we don't want to directly commit

This directory contains a tree of [gomplate](https://docs.gomplate.ca/) templates, in a hierarchy that mimics that of the [deployment](/deploy) directory.

While the **actual content** of a given Secret should not be committed to a repository directly, what we **do** with them is knowable.

These templates are expected to be rendered by a [simple script](/scripts/render-templates.sh) that takes care of putting everything into the right place, and the repository is [configured to ignore](/.gitignore) secrets in other directories, so you don't accidentally commit them.
