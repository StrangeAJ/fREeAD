import 'package:flutter_test/flutter_test.dart';
import 'package:freead/services/extraction/html_sanitizer.dart';

void main() {
  group('sanitize', () {
    test('removes scripts, styles and iframes entirely', () {
      const html = '''
<p>Keep me.</p>
<script>alert('x')</script>
<style>p{color:red}</style>
<iframe src="https://ads.example"></iframe>
<noscript><p>fallback</p></noscript>
''';
      final out = HtmlSanitizer.sanitize(html);
      expect(out, contains('Keep me.'));
      expect(out, isNot(contains('<script')));
      expect(out, isNot(contains('alert')));
      expect(out, isNot(contains('<style')));
      expect(out, isNot(contains('<iframe')));
      expect(out, isNot(contains('fallback')));
    });

    test('drops class, id, style and event handler attributes', () {
      const html =
          '<p class="promo" id="x" style="color:red" onclick="hack()">Text</p>';
      final out = HtmlSanitizer.sanitize(html);
      expect(out, contains('Text'));
      expect(out, isNot(contains('class=')));
      expect(out, isNot(contains('id=')));
      expect(out, isNot(contains('style=')));
      expect(out, isNot(contains('onclick')));
    });

    test('keeps the allow-listed attributes', () {
      const html =
          '<a href="https://e.com" title="t">l</a>'
          '<img src="https://e.com/a.png" alt="a" width="10" height="20">';
      final out = HtmlSanitizer.sanitize(html);
      expect(out, contains('href="https://e.com"'));
      expect(out, contains('title="t"'));
      expect(out, contains('alt="a"'));
      expect(out, contains('width="10"'));
    });

    test('resolves relative URLs against the base', () {
      const html =
          '<p><a href="/x/y">link</a></p><p><img src="img/pic.jpg" alt=""></p>';
      final out = HtmlSanitizer.sanitize(
        html,
        baseUrl: 'https://site.example/news/2026/story.html',
      );
      expect(out, contains('href="https://site.example/x/y"'));
      expect(
        out,
        contains('src="https://site.example/news/2026/img/pic.jpg"'),
      );
    });

    test('strips javascript: hrefs but keeps the text', () {
      const html = '<p><a href="javascript:steal()">click</a></p>';
      final out = HtmlSanitizer.sanitize(html);
      expect(out, contains('click'));
      expect(out, isNot(contains('javascript:')));
    });

    test('converts picture to the largest img candidate', () {
      const html = '''
<picture>
  <source srcset="/small.jpg 400w, /large.jpg 1600w">
  <img src="/fallback.jpg" alt="Photo">
</picture>
''';
      final out = HtmlSanitizer.sanitize(html, baseUrl: 'https://cdn.example/');
      expect(out, contains('<img'));
      expect(out, isNot(contains('<picture')));
      expect(out, contains('https://cdn.example/large.jpg'));
    });

    test('picks the largest srcset candidate for a plain img', () {
      const html =
          '<p><img src="/s.jpg" srcset="/s.jpg 320w, /xl.jpg 2000w" alt=""></p>';
      final out = HtmlSanitizer.sanitize(html, baseUrl: 'https://cdn.example/');
      expect(out, isNot(contains('srcset')));
    });

    test('removes tracking pixels', () {
      const html =
          '<p>Body text.</p>'
          '<img src="https://feeds.feedburner.com/~ff/beacon.gif" width="1" height="1">';
      final out = HtmlSanitizer.sanitize(html);
      expect(out, contains('Body text.'));
      expect(out, isNot(contains('<img')));
    });

    test('unwraps span wrappers and promotes inline divs to paragraphs', () {
      const html = '<div><span>Just inline text</span></div>';
      final out = HtmlSanitizer.sanitize(html);
      expect(out, contains('Just inline text'));
      expect(out, isNot(contains('<span')));
      expect(out, contains('<p>'));
    });

    test('removes empty blocks but keeps ones holding media', () {
      const html =
          '<p></p><p>   </p><p>Real</p><figure><img src="https://e.com/a.png"></figure>';
      final out = HtmlSanitizer.sanitize(html);
      expect(out, contains('Real'));
      expect(out, contains('<img'));
      expect('<p></p>'.allMatches(out).length, 0);
    });

    test('keeps structural article markup', () {
      const html =
          '<h2>Head</h2><ul><li>One</li><li>Two</li></ul>'
          '<blockquote>Quote</blockquote><pre><code>x=1</code></pre>'
          '<table><tr><td>c</td></tr></table><mark data-hl="1">hl</mark>';
      final out = HtmlSanitizer.sanitize(html);
      expect(out, contains('<h2>'));
      expect(out, contains('<li>'));
      expect(out, contains('<blockquote>'));
      expect(out, contains('<pre>'));
      expect(out, contains('<code>'));
      expect(out, contains('<td>'));
      expect(out, contains('data-hl="1"'));
    });

    test('empty input yields an empty string', () {
      expect(HtmlSanitizer.sanitize(''), '');
      expect(HtmlSanitizer.sanitize('   '), '');
    });
  });

  group('toPlainText', () {
    test('inserts newlines at block boundaries', () {
      const html = '<p>One</p><p>Two</p><h2>Three</h2>';
      final text = HtmlSanitizer.toPlainText(html);
      expect(text, 'One\nTwo\nThree');
    });

    test('drops script contents', () {
      const html = '<p>Visible</p><script>var hidden = 1;</script>';
      expect(HtmlSanitizer.toPlainText(html), 'Visible');
    });

    test('decodes entities', () {
      expect(HtmlSanitizer.toPlainText('<p>Tom &amp; Jerry</p>'), 'Tom & Jerry');
    });
  });

  group('excerpt', () {
    test('truncates on a word boundary with an ellipsis', () {
      final html = '<p>${'word ' * 200}</p>';
      final excerpt = HtmlSanitizer.excerpt(html, max: 40);
      expect(excerpt.length, lessThanOrEqualTo(43));
      expect(excerpt, endsWith('...'));
    });

    test('returns the whole text when it is short', () {
      expect(HtmlSanitizer.excerpt('<p>Short one.</p>'), 'Short one.');
    });
  });
}
