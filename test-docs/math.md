# Math

LaTeX math via `$…$` (inline) and `$$…$$` (display), typeset natively
with Latin Modern Math. No WebView, no MathJax.

## Inline

Einstein said $E = mc^2$, Pythagoras said $a^2 + b^2 = c^2$, and the
Greeks said $\alpha, \beta, \gamma, \ldots, \omega$. Subscripts like
$x_i$ and $a_{n+1}$; superscripts like $2^{10}$; both in $x_i^2$.

Functions and operators: $\sin^2\theta + \cos^2\theta = 1$,
$\log_2 n$, $\lim_{x \to 0} \frac{\sin x}{x} = 1$, $\nabla \cdot \vec{F}$.

Sets and logic: $x \in \mathbb{R}$, $A \subseteq B$, $\forall \epsilon > 0\, \exists \delta > 0$,
$\neg (p \land q) \iff \neg p \lor \neg q$.

Inline fractions and roots sit a touch high — a known limitation, see
the notes at the bottom: $\frac{1}{2}$, $\sqrt{2}$, $\sqrt[3]{x}$.

## Display

$$
\int_0^\infty e^{-x^2}\, dx = \frac{\sqrt{\pi}}{2}
$$

$$
\sum_{n=1}^{\infty} \frac{1}{n^2} = \frac{\pi^2}{6}
$$

Maxwell, in a single line: $$\nabla \times \mathbf{B} - \frac{1}{c^2}\frac{\partial \mathbf{E}}{\partial t} = \mu_0 \mathbf{J}$$

A blank line inside a display block is fine:

$$
f(x) = \begin{cases}
  1 & \text{if } x \in \mathbb{Q} \\

  0 & \text{otherwise}
\end{cases}
$$

Matrices:

$$
\begin{pmatrix} a & b \\ c & d \end{pmatrix}
\begin{bmatrix} x \\ y \end{bmatrix}
=
\begin{bmatrix} ax + by \\ cx + dy \end{bmatrix}
$$

Aligned equations:

$$
\begin{aligned}
(a + b)^2 &= (a + b)(a + b) \\
          &= a^2 + 2ab + b^2
\end{aligned}
$$

## In other blocks

- A list item with $\alpha + \beta$
- Display math inside a list item:
  $$\binom{n}{k} = \frac{n!}{k!\,(n-k)!}$$
- Nested list with $\hbar\omega$
  1. $\int f\, d\mu$
  2. $\oint_C \mathbf{F} \cdot d\mathbf{r}$

> Blockquote with $\Delta S \geq 0$, the second law.

| Symbol   | Meaning            |
|----------|--------------------|
| $\pi$    | circle constant    |
| $e$      | Euler's number     |
| $\phi$   | $\frac{1+\sqrt5}{2}$ |

### Heading with $\Sigma$ in it (math scales with the heading)

## $\pi$ at h2 size, $\frac{a}{b}$ too

## Beyond SwiftMath's built-ins

Symbols mdv registers itself: $a \gtrsim b$, $a \lesssim b$, $\therefore$,
$\because$, $p \implies q$, $\iint_D f\,dA$, $x_1, \dots, x_n$,
$\varnothing$, $\Box$, $\checkmark$, $\hookrightarrow$, $\rightleftharpoons$,
$\nexists$, $\leqslant$, $\#$, $\_$.

Commands rewritten into ones the parser knows: $\operatorname{argmax}_x f(x)$,
$a \bmod b$, $a \equiv b \pmod{n}$, $\dfrac{1}{2}$, $\boldsymbol{v}$, $x \coloneqq y$,
$a \not= b$, size hints dropped in $\big(p = h/N\big)$ and $\Bigl[\tfrac{1}{2}\Bigr]$,
and `align`/`equation`/`multline` environments:

$$
\begin{align*}
  \nabla \cdot \mathbf{E} &= \rho / \varepsilon_0 \\
  \nabla \cdot \mathbf{B} &= 0
\end{align*}
$$

Boxed: $\boxed{x}$, $\boxed{E = mc^2}$, and in display:

$$\boxed{M = P \cdot \frac{r(1+r)^n}{(1+r)^n - 1}}$$

Still unsupported (shows the source): $\underbrace{a+b}_{c}$,
$\stackrel{?}{=}$, $\substack{a \\ b}$, `\&`.

## Things that must NOT become math

- Prices: $5 and $10, or a range of $5-$10, or $100/month.
- Escaped dollars: \$x\$ stays literal.
- Inline code: `$HOME`, `$x^2$`, `echo $PATH`.
- A fenced block:

```bash
echo "$HOME costs $5"
export X=$((1 + 1))
```

- An empty pair `$$` on its own: $$

## Errors

An unbalanced brace shows the source instead of vanishing: $\frac{a$
and a bogus command in display:

$$
\notacommand{x}
$$

## Inside Mermaid

Node labels that are a single `$$…$$` span are typeset; text mixed with
math, and edge labels, get the Unicode approximation.

```mermaid
flowchart LR
    P["principal P"] --> OWED["$$P(1+r)^n$$"]
    OWED -->|"solve for M, $$r \ne 0$$"| M["$$M = P \cdot \frac{r(1+r)^n}{(1+r)^n - 1}$$"]
    M --> MIX["mixed: rate $$r$$ per period"]
```
