---
layout: post
title: "RubyLLM::Schema Is Now Schematist: A JSON Schema DSL for Ruby with Full Draft 2020-12 Coverage"
date: 2026-08-11
description: "RubyLLM::Schema is now Schematist: a general purpose JSON Schema DSL with full Draft 2020-12 coverage, values resolved at render time, and no runtime dependencies."
tags: [Ruby, JSON Schema, Open Source, Schematist, RubyLLM, AI]
sendfox_campaign_id: 2990216
image: /images/schematist.png
---
I want to make Ruby the best language to work with LLMs. Part of that is a great JSON Schema DSL.

[Schematist](https://github.com/crmne/schematist) is a general purpose JSON Schema DSL that emits Draft 2020-12 schemas. Describe an API payload, a config file, a contract between two services, or the structured output you want back from a model. Trapping that inside another gem's namespace was a disservice to anyone looking for a great JSON Schema DSL, so it got its own name.

```ruby
gem 'schematist'
```

## It Emits Actual JSON Schema

This is the breaking change.

`to_json_schema` used to return this:

```ruby
{ name: "PersonSchema", description: nil, schema: { type: "object", ... }, strict: true }
```

That's not a JSON Schema. It's OpenAI's `response_format` envelope, with the actual schema buried one level down under a symbol key. Every consumer that wasn't OpenAI had to dig it out, and anyone who wanted to hand the result to a validator had to know which part was real.

Now you get the document:

```ruby
class Invoice < Schematist::Schema
  title "Invoice"
  description "A billing document"

  string :id, pattern: "^inv_", title: "Invoice ID"
  number :total, greater_than: 0, description: "Amount due"
  string :currency, const: "EUR"
  string :status, enum: %w[draft sent paid], default: "draft"
end

Invoice.new.to_json_schema
# => {
#   "$schema" => "https://json-schema.org/draft/2020-12/schema",
#   "title" => "Invoice",
#   "description" => "A billing document",
#   "type" => "object",
#   "properties" => {
#     "id" => { "type" => "string", "pattern" => "^inv_", "title" => "Invoice ID" },
#     "total" => { "type" => "number", "description" => "Amount due", "exclusiveMinimum" => 0 },
#     ...
#   },
#   "required" => ["id", "total", "currency", "status"],
#   "additionalProperties" => false
# }
```

String keys, `$schema` declared, no provider keys. Use it with `JSON.generate` unchanged and any Draft 2020-12 validator will take it.

`strict` went with it. It's an OpenAI request flag, not a JSON Schema keyword, and a schema library has no business knowing OpenAI exists. Set it where you build the request.

## Full Draft 2020-12 Coverage

The old gem covered the basics: types, `enum`, `required`, string and numeric bounds, nested objects and arrays, `$defs` and `$ref`, `if`/`then`/`else`. [Schematist](https://github.com/crmne/schematist) covers the whole vocabulary.

**Composition.** `allOf`, `oneOf`, and `not` join `anyOf`:

```ruby
one_of :method do
  object { string :card_number }
  object { string :iban }
end

all_of :account, unevaluated_properties: false do
  object { string :id }
  object { string :status }
end

none_of :state do
  string enum: ["deleted"]
end
```

`unevaluated_properties` is the one that makes `allOf` usable in practice. `additionalProperties` can't see across composition branches; `unevaluatedProperties` can.

**Object keys.** Constrain how many properties an object has, what its keys look like, and what the values behind a key pattern must be:

```ruby
object :metadata, min_properties: 1, max_properties: 10 do
  keys { string pattern: "^[a-z_]+$" }     # propertyNames
  keys_matching(/^x-/) { string }          # patternProperties
end
```

**Arrays.** `uniqueItems`, fixed-length tuples via `prefixItems`, and `contains` with its bounds:

```ruby
array :tags, of: :string, unique: true

tuple :period do
  string format: "date"
  string format: "date"
end

array :scores do
  integer
  contains(min: 1) { integer minimum: 10 }   # at least one score of 10 or more
end
```

**Annotations.** `title`, `description`, `default`, `examples`, `deprecated`, `read_only`, `write_only`. Short ones read well as keyword arguments; longer ones read better in the block, where they annotate the enclosing schema:

```ruby
object :account do
  title "Account"
  description "Billing account metadata used for invoices."
  examples [{ id: "acct_123", status: "active" }]

  string :id
  string :status
end
```

**Encoded content.** For strings that carry something else inside them:

```ruby
string :payload, content_encoding: "base64", content_media_type: "application/json" do
  content_schema do
    object { string :name }
  end
end
```

**Core keywords.** `$id`, `$anchor`, `$comment`, `$dynamicAnchor`, `$dynamicRef`, `$vocabulary`, at the root or on any subschema. They're passed straight through. Resolving a dynamic reference is the validator's job, not ours.

Also new: `const` on every primitive, and `greater_than` / `less_than` for `exclusiveMinimum` / `exclusiveMaximum`. I picked the Ruby-sounding names over the JSON Schema ones on purpose. You're writing Ruby.

## Values That Aren't Known Until Render Time

You define a schema class once, at boot. The allowed values often aren't known until a request comes in.

Any value can be a proc now, resolved when the document is rendered:

```ruby
class RoleSchema < Schematist::Schema
  string :role, enum: -> { @account.roles.pluck(:name) }

  def initialize(account:)
    super()
    @account = account
  end
end

RoleSchema.new(account: account).to_json_schema
```

A zero-argument proc is evaluated in the instance's context, so it can read instance variables. A proc that takes one argument gets the schema instance instead. One class, a different document per instance.

## Escape Hatches

Covering the spec isn't the same as guessing everything you'll want to put in a document, so there are two ways out.

JSON Schema allows `true` and `false` in place of a schema object. `true` accepts anything, `false` accepts nothing:

```ruby
any_of :value do
  any_schema
  string
end
```

And `raw` drops a fragment in as-is, for a vendor extension or anything else the DSL has no opinion about:

```ruby
raw :vendor, { "type" => "object", "x-vendor" => true }
```

## A Schema Doesn't Have To Be an Object

Most schemas describe an object, so that's the default. But JSON Schema doesn't care. A schema can be an array, a union, a string, or a pointer somewhere else, and the root of a document is just a schema like any other.

So: a type with a name declares a property. Without a name, it declares what the schema itself is.

```ruby
class Tags < Schematist::Schema
  array of: :string, unique: true       # the whole schema is an array
end

class Id < Schematist::Schema
  one_of do                             # the whole schema is a choice
    string
    integer
  end
end

class Person < Schematist::Schema
  raw({ "$ref" => "https://example.com/person.json" })
end
```

It works inside `define` too, so a reusable definition can be a string with a pattern or a shared enum, not just an object:

```ruby
define :status do
  string enum: %w[draft sent paid]
end
```

A conditional branch is a schema too, so it can ask for a nested object instead of a flat list of fields:

```ruby
given kind: "business" do
  requires :vat_id

  object :tax_details do
    string :vat_number
  end
end
```

## No Runtime Dependencies

[Schematist](https://github.com/crmne/schematist) depends on nothing.

## Migrating

```ruby
gem 'schematist'                         # was: gem 'ruby_llm-schema'

class Person < Schematist::Schema        # was: RubyLLM::Schema
end
```

Errors moved up a level: `Schematist::ValidationError`, not `RubyLLM::Schema::ValidationError`. `Schematist::Helpers` replaces `RubyLLM::Helpers`.

If you were reaching into `[:schema]` to get at the document, stop. `to_json_schema` returns it directly now, with string keys. If you need the provider wrapper, build it where you send the request:

```ruby
{ name: "Invoice", schema: Invoice.new.to_json_schema, strict: true }
```

There's a final `ruby_llm-schema` 1.0.0 that depends on [Schematist](https://github.com/crmne/schematist) and aliases the old constants, so `RubyLLM::Schema` keeps resolving while you move. It warns on load and it's the last release of that name.

RubyLLM 2.0 will depend on Schematist, so structured output will get a lot more powerful.

## Use It

```bash
bundle add schematist
```

[Schematist](https://github.com/crmne/schematist) was always a JSON Schema DSL. Now it has the name to match.
