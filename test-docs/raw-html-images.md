# Raw HTML images

GitHub sanitises HTML and renders `<img>` tags, so READMEs reach for them
for what Markdown cannot express — most often a sized header image. mdv has
no HTML renderer, so `RawHTMLImages` rewrites each `<img>` tag into an image
reference its own providers understand, carrying the size the tag asked for.
Everything else in the HTML is left alone and keeps printing as text.

## A sized header, the README pattern

<img src="../MDV.png" alt="mdv" width="320">

## Width, height, and neither

Width only, so the height follows the aspect:

<img src="../MDV.png" alt="width only" width="180">

Both, which fit inside the pair without stretching:

<img src="../MDV.png" alt="bounded" width="240" height="80">

A lone height, deriving the width:

<img src="../MDV.png" alt="height only" height="60">

No attributes at all: the image's own size, which the column may shrink.

<img src="../MDV.png" alt="natural size">

## Inline, in the middle of a sentence

This paragraph has one in it — <img src="../MDV.png" alt="inline" width="120">
— and the text should flow around the image, both on screen and in print.

A plain Markdown image inline works the same way: ![small icon](images/icon.png)
sits in this sentence, and prints.

## Quotes

Single quotes work: <img src='../MDV.png' alt='single' width="100">.

Bare attribute values work too: <img src=../MDV.png alt=bare width=90>.

## Failures and non-images

A missing file leaves the alt text: <img src="nope.png" alt="missing file" width="200">.

Remote sources go through the same gate as any other remote image:

<img src="https://github.githubassets.com/images/modules/logos_page/Octocat.png" alt="octocat" width="120">

## What must stay literal

A fenced block keeps its HTML as HTML:

```
<img src="not-an-image.png" width="320">
```

Inline code keeps it too: `<img src="also-not-an-image.png">`.

An `<a>` tag is not an image tag and renders as text: <a href="#">a link</a>.
