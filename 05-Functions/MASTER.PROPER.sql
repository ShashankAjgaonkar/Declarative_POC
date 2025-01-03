CREATE OR REPLACE FUNCTION {{environment}}_INGESTION_DB.MASTER.PROPER("EXPRESSION" VARCHAR(16777216), "DOPATTERNMATCH" BOOLEAN)
RETURNS VARCHAR(16777216)
LANGUAGE JAVASCRIPT
AS '
if (typeof EXPRESSION === ''undefined'') {

  return null;

}
var i = 1;

var l = EXPRESSION.length;

var c;

var f = 1;

var o = '''';

var w = ''[\\r\\n\\t\\u00A0 -]'';

while (i <= l) 
{

  c = EXPRESSION.substring(i - 1, i);

  if (f === 1) {

    o += c.toUpperCase();

    f = 0;

  } else {

    o += c.toLowerCase();

  }

  if (c.match(w)) {

    f = 1;

  }

  i += 1;

}if (DOPATTERNMATCH) {

  // Fix Mcsomething to McSomething

  if (o.startsWith(''Mc'')) {

    o = ''Mc'' + o.charAt(2).toUpperCase() + o.slice(3);

  }  // Using a regex to find all occurrences of Mc followed by a lowercase letter

  var regex = /Mc([a-z])/g;

  var match;

  while ((match = regex.exec(o)) !== null) {

    var index = match.index;

    o = o.slice(0, index + 2) + o.charAt(index + 2).toUpperCase() + o.slice(index + 3);

  }  // Fix St. to Saint

  o = o.replace(/St\\. /g, ''Saint '');  // Fix Ft. to Fort

  o = o.replace(/Ft\\. /g, ''Fort '');

}
return o;

';