// Adds one release to docs/appcast.xml (newest first), for Sparkle.
// Usage: node appcast.js <appcast.xml> <version> <build> <zipURL> <length> <edSignature> <notesFile>
const fs = require('fs');
const [,, file, version, build, url, length, signature, notesFile] = process.argv;
if (!notesFile) { console.error('usage: appcast.js <appcast.xml> <version> <build> <zipURL> <length> <edSignature> <notesFile>'); process.exit(2); }
const notes = fs.readFileSync(notesFile, 'utf8').trim();
const escape = s => s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const item = `    <item>
      <title>Tibber Menu Bar ${version}</title>
      <pubDate>${new Date().toUTCString().replace('GMT', '+0000')}</pubDate>
      <sparkle:version>${build}</sparkle:version>
      <sparkle:shortVersionString>${version}</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>14.0.0</sparkle:minimumSystemVersion>
      <link>https://robinnewstory.github.io/tibber-menu-bar/</link>
      <description sparkle:format="markdown"><![CDATA[${notes}]]></description>
      <enclosure url="${escape(url)}" length="${length}" type="application/octet-stream" sparkle:edSignature="${signature}"/>
    </item>
`;
let xml = fs.existsSync(file) ? fs.readFileSync(file, 'utf8') : '';
if (!xml.includes('<channel>')) {
  xml = `<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle" xmlns:dc="http://purl.org/dc/elements/1.1/">
  <channel>
    <title>Tibber Menu Bar</title>
    <link>https://robinnewstory.github.io/tibber-menu-bar/appcast.xml</link>
    <description>Updates for Tibber Menu Bar</description>
    <language>en</language>
  </channel>
</rss>
`;
}
if (xml.includes(`<sparkle:version>${build}</sparkle:version>`)) { console.error(`build ${build} is already in the appcast`); process.exit(1); }
xml = xml.replace(/(    <language>en<\/language>\n)/, `$1${item}`);
fs.writeFileSync(file, xml);
console.log(`appcast: added ${version} (${build})`);
