#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"

#include "gumbo.h"
#include <xs_object_magic.h>

#define PHG_IS_VOID_ELEMENT(tag) \
    (  tag == GUMBO_TAG_AREA \
    || tag == GUMBO_TAG_BASE \
    || tag == GUMBO_TAG_BR \
    || tag == GUMBO_TAG_COL \
    || tag == GUMBO_TAG_EMBED \
    || tag == GUMBO_TAG_HR \
    || tag == GUMBO_TAG_IMG \
    || tag == GUMBO_TAG_INPUT \
    || tag == GUMBO_TAG_KEYGEN \
    || tag == GUMBO_TAG_LINK \
    || tag == GUMBO_TAG_META \
    || tag == GUMBO_TAG_PARAM \
    || tag == GUMBO_TAG_SOURCE \
    || tag == GUMBO_TAG_TRACK \
    || tag == GUMBO_TAG_WBR )

#define newSVpvz8(str) \
    newSVpvn_utf8((str), strlen(str), 1)

#define newSVpvn8(str, len) \
    newSVpvn_utf8((str), (len), 1)

typedef enum {
    PHG_ELEMENT_START,
    PHG_ELEMENT_END,
    PHG_TEXT
} PerlHtmlGumboType;

STATIC
void
walk_tree(pTHX_ GumboNode* node, void (*cb)(pTHX_ PerlHtmlGumboType, GumboNode*, void*), void* ctx ) {
    if ( node->type == GUMBO_NODE_DOCUMENT || node->type == GUMBO_NODE_ELEMENT ) {
        GumboVector* children;
        (*cb)(aTHX_ PHG_ELEMENT_START, node, ctx);
        if ( node->type == GUMBO_NODE_DOCUMENT ) {
            children = &node->v.document.children;
        } else {
            children = &node->v.element.children;
        }
        if (children) {
            int i = 0;
            for (i = 0; i < children->length; ++i) {
                walk_tree(aTHX_ children->data[i], cb, ctx);
            }
        }
        (*cb)(aTHX_ PHG_ELEMENT_END, node, ctx);
    } else {
        (*cb)(aTHX_ PHG_TEXT, node, ctx);
    }
}

STATIC
GumboStringPiece
get_tag_name(GumboElement* e) {
    GumboStringPiece res;
    if ( e->tag == GUMBO_TAG_UNKNOWN ) {
        res = e->original_tag;
        gumbo_tag_from_original_text(&res);
    } else {
        res.data = gumbo_normalized_tagname(e->tag);
        res.length = strlen(res.data);
    }
    return res;
}

STATIC void
out_attr_value(SV* out, const char* v) {
    STRLEN i;
    STRLEN prev = 0;
    STRLEN len = strlen(v);
    for ( i = 0; i < len; i++ ) {
        if (v[i] != '"' && v[i] != '&' )
            continue;
        if (i != prev)
            sv_catpvn(out, v+prev, i-prev);
        sv_catpv(out, v[i] == '&'? "&amp;": "&quot;");
        prev = ++i;
    }
    if (prev < len)
        sv_catpvn(out, v+prev, len-prev);
}

STATIC void
out_text(SV* out, const char* v) {
    STRLEN i;
    STRLEN prev = 0;
    STRLEN len = strlen(v);
    for ( i = 0; i < len; i++ ) {
        if (v[i] != '<' && v[i] != '>' && v[i] != '&' )
            continue;
        if (i != prev)
            sv_catpvn(out, v+prev, i-prev);
        sv_catpv(out, v[i] == '&'? "&amp;": (v[i] == '<'? "&lt;" : "&gt;"));
        prev = ++i;
    }
    if (prev < len)
        sv_catpvn(out, v+prev, len-prev);
}

STATIC void
out_tag_start_line(SV* out, GumboElement* e) {
    int i;
    GumboStringPiece piece = get_tag_name(e);

    sv_catpvs(out, "<");
    sv_catpvn(out, piece.data, piece.length);
    for (i = 0; i < e->attributes.length; i++) {
        GumboAttribute* attr = (GumboAttribute*) e->attributes.data[i];
        sv_catpvs(out, " ");
        sv_catpv(out, attr->name);
        if (strlen(attr->value)) {
            sv_catpvs(out, "=\"");
            out_attr_value(out, attr->value);
            sv_catpvs(out, "\"");
        }
    }
    sv_catpvs(out, ">");

    return;
}

STATIC void
out_tag_end_line(SV* out, GumboElement* e) {
    GumboStringPiece piece;
    if ( PHG_IS_VOID_ELEMENT(e->tag))
        return;

    sv_catpvs(out, "</");
    piece = get_tag_name(e);
    sv_catpvn(out, piece.data, piece.length);
    sv_catpvs(out, ">");

    return;
}

STATIC void
out_doctype_text( SV* out, GumboDocument* doc ) {
    sv_catpvs(out, "DOCTYPE");
    if (strlen(doc->name)>0) {
        sv_catpvs(out, " ");
        sv_catpv(out, doc->name);
    }
    if (strlen(doc->public_identifier)>0) {
        sv_catpvs(out, " PUBLIC \"");
        sv_catpv(out, doc->public_identifier);
        sv_catpvs(out, "\"");
    }
    if (strlen(doc->system_identifier)>0) {
        sv_catpvs(out, " \"");
        sv_catpv(out, doc->system_identifier);
        sv_catpvs(out, "\"");
    }
}

STATIC void
out_doctype( SV* out, GumboDocument* doc ) {
    sv_catpvs(out, "<!");
    out_doctype_text(out, doc);
    sv_catpvs(out, ">\n");
}

STATIC void
tree_to_string(pTHX_ PerlHtmlGumboType type, GumboNode* node, void* ctx) {
    SV* out = (SV*) ctx;
    if ( type == PHG_TEXT ) {
        if ( node->type == GUMBO_NODE_COMMENT ) {
            sv_catpvs(out, "<!--");
        }
        else if ( node->type == GUMBO_NODE_CDATA ) {
            sv_catpvs(out, "<![CDATA[");
        }
        if ( node->type == GUMBO_NODE_TEXT ) {
            out_text(out, node->v.text.text);
        } else {
            sv_catpv(out, node->v.text.text);
        }
        if ( node->type == GUMBO_NODE_COMMENT ) {
            sv_catpvs(out, "-->");
        }
        else if ( node->type == GUMBO_NODE_CDATA ) {
            sv_catpvs(out, "]]>");
        }
    }
    else if ( type == PHG_ELEMENT_START && node->type == GUMBO_NODE_DOCUMENT ) {
        GumboDocument* doc = &node->v.document;
        if ( doc->has_doctype )
            out_doctype(out, doc);
    }
    else if ( type == PHG_ELEMENT_END && node->type == GUMBO_NODE_DOCUMENT ) {
        sv_catpvs(out, "\n");
    }
    else if ( type == PHG_ELEMENT_START ) {
        GumboElement* e = &node->v.element;
        out_tag_start_line(out, e);
        if ( e->tag == GUMBO_TAG_PRE || e->tag == GUMBO_TAG_TEXTAREA ) {
            sv_catpvs(out, "\n");
        }
    }
    else if ( type == PHG_ELEMENT_END ) {
        GumboElement* e = &node->v.element;
        out_tag_end_line(out, e);
    }
    return;
}

STATIC SV*
new_html_element(pTHX_ GumboNode* node) {
    dSP;
    SV* res;
    int rcount;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    mXPUSHs(newSVpvs("HTML::Element"));
    if ( node->type == GUMBO_NODE_DOCUMENT ) {
        mXPUSHs(newSVpvs("document"));
    }
    else if ( node->type == GUMBO_NODE_ELEMENT ) {
        int i;
        GumboVector* attrs = &node->v.element.attributes;
        GumboStringPiece tag = get_tag_name(&node->v.element);
        mXPUSHs(newSVpvn8( tag.data, tag.length ));
        for (i = 0; i < attrs->length; i++) {
            GumboAttribute* attr = (GumboAttribute*) attrs->data[i];
            mXPUSHs(newSVpvz8( attr->name ));
            mXPUSHs(newSVpvz8( attr->value ));
        }
    }
    else if ( node->type == GUMBO_NODE_COMMENT ) {
        mXPUSHs(newSVpvs("~comment"));
        mXPUSHs(newSVpvs("text"));
        mXPUSHs(newSVpvz8( node->v.text.text ));
    }
    else {
        croak("Unknown node type");
    }
    PUTBACK;

    rcount = call_method("new", G_SCALAR);

    SPAGAIN;

    if (rcount != 1) croak("Big trouble\n");

    res = SvREFCNT_inc_NN(POPs);
    PUTBACK;

    FREETMPS;
    LEAVE;

    return res;
}

STATIC SV*
new_html_element_doctype(pTHX_ GumboDocument* doc) {
    dSP;
    SV* res;
    SV* doctype;
    int rcount;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    mXPUSHs(newSVpvs("HTML::Element"));
    mXPUSHs(newSVpvs("~declaration"));
    mXPUSHs(newSVpvs("text"));
    doctype = newSVpvn8( "",0 );
    out_doctype_text(doctype, doc);
    mXPUSHs(doctype);
    PUTBACK;

    rcount = call_method("new", G_SCALAR);

    SPAGAIN;

    if (rcount != 1) croak("Big trouble\n");

    res = SvREFCNT_inc_NN(POPs);
    PUTBACK;

    FREETMPS;
    LEAVE;

    return res;
}


STATIC void
push_element(pTHX_ SV* parent, SV* element) {
    dSP;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(parent);
    XPUSHs(element);
    PUTBACK;

    call_method("push_content", G_DISCARD);

    FREETMPS;
    LEAVE;
}

STATIC void
push_text_element(pTHX_ SV* parent, const char *const s, const STRLEN len) {
    dSP;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(parent);
    mXPUSHs(newSVpv(s, len));
    PUTBACK;

    call_method("push_content", G_DISCARD);

    FREETMPS;
    LEAVE;
}

STATIC SV*
get_element_parent(pTHX_ SV* element) {
    dSP;
    SV* res;
    int rcount;

    ENTER;
    SAVETMPS;
    PUSHMARK(SP);
    XPUSHs(element);
    PUTBACK;

    rcount = call_method("parent", G_SCALAR);

    SPAGAIN;

    if (rcount != 1) croak("Big trouble\n");

    res = SvREFCNT_inc_NN(POPs);
    PUTBACK;

    FREETMPS;
    LEAVE;

    return res;
}

STATIC void
tree_to_tree(pTHX_ PerlHtmlGumboType type, GumboNode* node, void* ctx) {
    SV** out = (SV**) ctx;
    if ( type == PHG_TEXT ) {
        if ( node->type == GUMBO_NODE_COMMENT ) {
            SV* element = new_html_element(aTHX_ node);
            push_element(aTHX_ *out, element);
            SvREFCNT_dec(element);
        } else {
            push_text_element(*out, node->v.text.text, 0);
        }
    }
    else if ( type == PHG_ELEMENT_START && node->type == GUMBO_NODE_DOCUMENT ) {
        GumboDocument* doc = &node->v.document;
        *out = new_html_element(aTHX_ node);
        sv_2mortal(*out);
        if ( doc->has_doctype ) {
            SV* element = new_html_element_doctype(aTHX_ doc);
            push_element(aTHX_ *out, element);
            SvREFCNT_dec(element);
        }
    }
    else if ( type == PHG_ELEMENT_END && node->type == GUMBO_NODE_DOCUMENT ) {
    }
    else if ( type == PHG_ELEMENT_START ) {
        SV* element = new_html_element(aTHX_ node);
        push_element(aTHX_ *out, element);
        *out = element;
    }
    else if ( type == PHG_ELEMENT_END ) {
        SV* parent = get_element_parent(aTHX_ *out);
        SvREFCNT_dec(*out);
        *out = parent;
    }
    return;
}

STATIC void
tree_to_callback(pTHX_ PerlHtmlGumboType type, GumboNode* node, void* ctx) {
    dSP;
    SV* cb = (SV*) ctx;

    if ( type == PHG_ELEMENT_END && PHG_IS_VOID_ELEMENT(node->v.element.tag) )
        return;

    ENTER;
    SAVETMPS;

    PUSHMARK(SP);
    if ( type == PHG_TEXT ) {
        switch ( node->type ) {
            case GUMBO_NODE_TEXT:
                mXPUSHs(newSVpvs("text"));break;
            case GUMBO_NODE_WHITESPACE:
                mXPUSHs(newSVpvs("space"));break;
            case GUMBO_NODE_CDATA:
                mXPUSHs(newSVpvs("cdata"));break;
            case GUMBO_NODE_COMMENT:
                mXPUSHs(newSVpvs("comment"));break;
            default:
                croak("Unknown node type");
        }
        mXPUSHs(newSVpvz8( node->v.text.text ));
    }
    else if ( type == PHG_ELEMENT_START && node->type == GUMBO_NODE_DOCUMENT ) {
        GumboDocument* doc = &node->v.document;
        mXPUSHs(newSVpvs("document start"));
        if ( doc->has_doctype ) {
            HV* h = newHV();
            mXPUSHs(newRV_noinc((SV*)h));
            (void)hv_stores(h, "name", newSVpvz8( doc->name ));
            (void)hv_stores(h, "public", newSVpvz8( doc->public_identifier ));
            (void)hv_stores(h, "system", newSVpvz8( doc->system_identifier ));
        } else {
            mXPUSHs(&PL_sv_undef);
        }
    }
    else if ( type == PHG_ELEMENT_END && node->type == GUMBO_NODE_DOCUMENT ) {
        mXPUSHs(newSVpvs("document end"));
    }
    else if ( type == PHG_ELEMENT_START ) {
        int i;
        GumboVector* attrs = &node->v.element.attributes;
        GumboStringPiece tag = get_tag_name(&node->v.element);
        AV* for_attrs = newAV();

        mXPUSHs(newSVpvs("start"));
        mXPUSHs(newSVpvn8( tag.data, tag.length ));
        mXPUSHs(newRV_noinc((SV*)for_attrs));
        for (i = 0; i < attrs->length; i++) {
            GumboAttribute* attr = (GumboAttribute*) attrs->data[i];
            av_push(for_attrs, newSVpvz8( attr->name ));
            av_push(for_attrs, newSVpvz8( attr->value ));
        }
    }
    else if ( type == PHG_ELEMENT_END ) {
        GumboStringPiece tag = get_tag_name(&node->v.element);
        mXPUSHs(newSVpvs("end"));
        mXPUSHs(newSVpvn8( tag.data, tag.length ));
    }

    PUTBACK;

    call_sv(cb, G_DISCARD);

    FREETMPS;
    LEAVE;

    return;
}

STATIC
char* prepare_buffer(pTHX_ SV* buffer) {
    if(!SvROK(buffer))
        croak("First argument is not a reference");

    buffer = SvRV(buffer);
    return SvPV_nolen(buffer);
}

MODULE = HTML::Gumbo    PACKAGE = HTML::Gumbo

SV*
parse_to_string(self, buffer, ...)
    SV *self
    SV *buffer

    CODE:
        const char* str = prepare_buffer(aTHX_ buffer);

        RETVAL = newSVpvn8("", 0);

        GumboOutput* output = gumbo_parse(str);
        walk_tree(aTHX_ output->document, tree_to_string, (void*)RETVAL);
        gumbo_destroy_output(&kGumboDefaultOptions, output);

    OUTPUT: RETVAL

SV*
parse_to_tree(self, buffer, ...)
    SV *self
    SV *buffer

    CODE:
        const char* str;
        load_module(
            0,
            newSVpvs("HTML::TreeBuilder"),
            newSViv(5), newSVpvs("-weak"), NULL
        );
        str = prepare_buffer(aTHX_ buffer);

        SV* res;
        GumboOutput* output = gumbo_parse(str);
        walk_tree(aTHX_ output->document, tree_to_tree, (void*)(&res));
        gumbo_destroy_output(&kGumboDefaultOptions, output);
        RETVAL = res;

    OUTPUT: RETVAL

void
_parse_to_callback(self, buffer, cb, ...)
    SV *self
    SV *buffer
    SV *cb

    CODE:
        const char* str = prepare_buffer(aTHX_ buffer);

        GumboOutput* output = gumbo_parse(str);
        walk_tree(aTHX_ output->document, tree_to_callback, (void*)cb);
        gumbo_destroy_output(&kGumboDefaultOptions, output);

        XSRETURN_YES;

SV*
parse_to_gumbo(self, buffer, ...)
    SV *self
    SV *buffer

    CODE:
        const char* str;
        load_module(
            0,
            newSVpvs("HTML::Gumbo::Result"),
            NULL, NULL
        );
        str = prepare_buffer(aTHX_ buffer);

        GumboOutput* output = gumbo_parse(str);
        RETVAL = xs_object_magic_create(aTHX_ (void*)output, gv_stashpv("HTML::Gumbo::Result", 0));

    OUTPUT: RETVAL

MODULE = HTML::Gumbo::Result    PACKAGE = HTML::Gumbo::Result

SV*
document(self)
    SV* self
    CODE:
        GumboOutput* output = xs_object_magic_get_struct_rv(aTHX_ self);
        RETVAL = xs_object_magic_create(aTHX_ (void*)output->document, gv_stashpv("HTML::Gumbo::Document", 0));
    OUTPUT: RETVAL

void
DESTROY(self)
    SV* self
    CODE:
        GumboOutput* output = xs_object_magic_get_struct_rv(aTHX_ self);
        if (output)
            gumbo_destroy_output(&kGumboDefaultOptions, output;
        xs_object_magic_detach_struct(aTHX_ self);

