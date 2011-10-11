
//          Copyright Ferdinand Majerech 2011.
// Distributed under the Boost Software License, Version 1.0.
//    (See accompanying file LICENSE_1_0.txt or copy at
//          http://www.boost.org/LICENSE_1_0.txt)

/**
 * YAML dumper.
 * Code based on PyYAML: http://www.pyyaml.org
 */
module dyaml.dumper;


import std.stream;
import std.typecons;

import dyaml.anchor;
import dyaml.emitter;
import dyaml.encoding;
import dyaml.event;
import dyaml.exception;
import dyaml.linebreak;
import dyaml.node;
import dyaml.representer;
import dyaml.resolver;
import dyaml.serializer;
import dyaml.tagdirectives;


/**
 * Dumps YAML documents to files or streams.
 *
 * User specified Representer and/or Resolver can be used to support new 
 * tags / data types.
 *
 * Setters are provided to affect the output (style, encoding)..
 * 
 * Examples: 
 *
 * Write to a file:
 * --------------------
 * auto node = Node([1, 2, 3, 4, 5]);
 * Dumper("file.txt").dump(node);
 * --------------------
 *
 * Write multiple YAML documents to a file:
 * --------------------
 * auto node1 = Node([1, 2, 3, 4, 5]);
 * auto node2 = Node("This document contains only one string");
 * Dumper("file.txt").dump(node1, node2);
 * --------------------
 *
 * Write to memory:
 * --------------------
 * import std.stream;
 * auto stream = new MemoryStream();
 * auto node = Node([1, 2, 3, 4, 5]);
 * Dumper(stream).dump(node);
 * --------------------
 *
 * Use a custom representer/resolver to support custom data types and/or implicit tags:
 * --------------------
 * auto node = Node([1, 2, 3, 4, 5]);
 * auto representer = new Representer();
 * auto resolver = new Resolver();
 *
 * //Add representer functions / resolver expressions here...
 * --------------------
 * auto dumper = Dumper("file.txt");
 * dumper.representer = representer;
 * dumper.resolver = resolver;
 * dumper.dump(node);
 * --------------------
 */
struct Dumper
{
    unittest
    {
        auto node = Node([1, 2, 3, 4, 5]);
        Dumper(new MemoryStream()).dump(node);
    }
   
    unittest
    {
        auto node1 = Node([1, 2, 3, 4, 5]);
        auto node2 = Node("This document contains only one string");
        Dumper(new MemoryStream()).dump(node1, node2);
    }
       
    unittest
    {
        import std.stream;
        auto stream = new MemoryStream();
        auto node = Node([1, 2, 3, 4, 5]);
        Dumper(stream).dump(node);
    }
       
    unittest
    {
        auto node = Node([1, 2, 3, 4, 5]);
        auto representer = new Representer();
        auto resolver = new Resolver();
        auto dumper = Dumper(new MemoryStream());
        dumper.representer = representer;
        dumper.resolver = resolver;
        dumper.dump(node);
    }

    private:
        ///Resolver to resolve tags.
        Resolver resolver_;
        ///Representer to represent data types.
        Representer representer_;

        ///Stream to write to.
        Stream stream_;

        ///Write scalars in canonical form?
        bool canonical_;
        ///Indentation width.
        int indent_ = 2;
        ///Preferred text width.
        uint textWidth_ = 80;
        ///Line break to use.
        LineBreak lineBreak_ = LineBreak.Unix;
        ///Character encoding to use.
        Encoding encoding_ = Encoding.UTF_8;
        ///YAML version string.
        string YAMLVersion_ = "1.1";
        ///Tag directives to use.
        TagDirectives tags_ = TagDirectives();
        ///Always write document start?
        bool explicitStart_ = false;
        ///Always write document end?
        bool explicitEnd_ = false;

    public:
        @disable this();

        /**
         * Construct a Dumper writing to a file.
         *
         * Params: filename = File name to write to.
         *
         * Throws: YAMLException if the file can not be dumped to (e.g. cannot be read).
         */
        this(string filename)
        {
            try{this(new File(filename));}
            catch(StreamException e)
            {
                throw new YAMLException("Unable to use file for YAML dumping " ~ filename ~ " : " ~ e.msg);
            }
        }

        ///Construct a Dumper writing to a stream. This is useful to e.g. write to memory.
        this(Stream stream)
        {
            resolver_ = new Resolver();
            representer_ = new Representer();
            stream_ = stream;
            Anchor.addReference();
            TagDirectives.addReference();
        }

        ///Destroy the Dumper.
        ~this()
        {
            Anchor.removeReference();
            TagDirectives.removeReference();
            YAMLVersion_ = null;
        }

        ///Specify custom Resolver to use.
        void resolver(Resolver resolver)
        {
            clear(resolver_);
            resolver_ = resolver;
        }

        ///Specify custom Representer to use.
        void representer(Representer representer)
        {
            clear(representer_);
            representer_ = representer;
        }

        ///Write scalars in canonical form?
        void canonical(in bool canonical)
        {
            canonical_ = canonical;
        }

        ///Set indentation width. 2 by default. Must not be zero.
        void indent(in uint indent)
        in
        {   
            assert(indent != 0, "Can't use zero YAML indent width");
        }
        body
        {
            indent_ = indent;
        }

        ///Set preferred text width.
        void textWidth(in uint width)
        {
            textWidth_ = width;
        }

        ///Set line break to use. Unix by default.
        void lineBreak(in LineBreak lineBreak)
        {
            lineBreak_ = lineBreak;
        }

        ///Set character encoding to use. UTF-8 by default.
        void encoding(in Encoding encoding)
        {
            encoding_ = encoding;
        }    

        ///Always explicitly write document start?
        void explicitStart(in bool explicit)
        {
            explicitStart_ = explicit;
        }

        ///Always explicitly write document end?
        void explicitEnd(in bool explicit)
        {
            explicitEnd_ = explicit;
        }

        ///Specify YAML version string. "1.1" by default.
        void YAMLVersion(in string YAMLVersion)
        {
            YAMLVersion_ = YAMLVersion;
        }

        /**
         * Specify tag directives. 
         *
         * A tag directive specifies a shorthand notation for specifying tags.
         * Each tag directive associates a handle with a prefix. This allows for 
         * compact tag notation.
         *
         * Each handle specified MUST start and end with a '!' character
         * (a single character "!" handle is allowed as well).
         *
         * Only alphanumeric characters, '-', and '_' may be used in handles.
         *
         * Each prefix MUST not be empty.
         *
         * The "!!" handle is used for default YAML tags with prefix 
         * "tag:yaml.org,2002:". This can be overridden.
         *
         * Params:  tags = Tag directives (keys are handles, values are prefixes).
         *
         * Example:
         * --------------------
         * Dumper dumper = Dumper("file.txt");
         * //This will emit tags starting with "tag:long.org,2011"
         * //with a "!short!" prefix instead.
         * dumper.tags("short", "tag:long.org,2011:");
         * dumper.dump(Node("foo"));
         * --------------------
         */
        void tagDirectives(string[string] tags)
        {
            Tuple!(string, string)[] t;
            foreach(handle, prefix; tags)
            {
                assert(handle.length >= 1 && handle[0] == '!' && handle[$ - 1] == '!',
                       "A tag handle is empty or does not start and end with a "
                       "'!' character : " ~ handle);
                assert(prefix.length >= 1, "A tag prefix is empty");
                t ~= tuple(handle, prefix);
            }
            tags_ = TagDirectives(t);
        }

        /**
         * Dump one or more YAML documents to the file/stream.
         *
         * Note that while you can call dump() multiple times on the same 
         * dumper, you will end up writing multiple YAML "files" to the same
         * file/stream.
         *
         * Params:  documents = Documents to dump (root nodes of the documents).
         *
         * Throws:  YAMLException on error (e.g. invalid nodes, 
         *          unable to write to file/stream).
         */
        void dump(Node[] documents ...)
        {
            try
            {
                auto emitter = Emitter(stream_, canonical_, indent_, textWidth_, lineBreak_);
                auto serializer = Serializer(emitter, resolver_, encoding_, explicitStart_,
                                             explicitEnd_, YAMLVersion_, tags_);
                foreach(ref document; documents)
                {
                    representer_.represent(serializer, document);
                }
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to dump YAML: " ~ e.msg);
            }
        }

    package:
        /*
         * Emit specified events. Used for debugging/testing.
         *
         * Params:  events = Events to emit.
         *
         * Throws:  YAMLException if unable to emit.
         */
        void emit(in Event[] events)
        {
            try
            {
                auto emitter = Emitter(stream_, canonical_, indent_, textWidth_, lineBreak_);
                foreach(ref event; events)
                {
                    emitter.emit(event);
                }
            }
            catch(YAMLException e)
            {
                throw new YAMLException("Unable to emit YAML: " ~ e.msg);
            }
        }
}