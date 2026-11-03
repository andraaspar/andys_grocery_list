import 'package:andys_grocery_list/model/markdown_codec.dart';
import 'package:andys_grocery_list/model/number_parser.dart';
import 'package:andys_grocery_list/model/todo_document.dart';

/// Builds a document from Markdown.
TodoDocument doc(String md) => parseDocument(md);

/// Serializes a document back to Markdown (English locale).
String md(TodoDocument d) => serializeDocument(d, NumberContext.en);

/// The id of the item at [list], [item].
String idAt(TodoDocument d, int list, int item) => d.lists[list].items[item].id;
