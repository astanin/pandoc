{-
Copyright (c) 2011, Sergey Astanin
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

    * Redistributions of source code must retain the above copyright notice,
      this list of conditions and the following disclaimer.
    * Redistributions in binary form must reproduce the above copyright notice,
      this list of conditions and the following disclaimer in the documentation
      and/or other materials provided with the distribution.
    * Neither the name of the Sergey Astanin nor the names of other
      contributors may be used to endorse or promote products derived from this
      software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

-}

{- | Conversion of 'Pandoc' documents to FB2 (FictionBook2) format.

FictionBook is an XML-based e-book format. For more information see:
<http://www.fictionbook.org/index.php/Eng:XML_Schema_Fictionbook_2.1>

-}
module Text.Pandoc.Writers.FB2 (writeFB2)  where

import Data.Char (toUpper)
import Text.XML.Light

import Text.Pandoc.Definition
import Text.Pandoc.Shared (WriterOptions, orderedListMarkers)
import Text.Pandoc.Generic (bottomUp)

-- | Produce an FB2 document from a 'Pandoc' document.
writeFB2 :: WriterOptions    -- ^ conversion options
         -> Pandoc           -- ^ document to convert
         -> String           -- ^ FictionBook2 document (not encoded yet)
writeFB2 _ (Pandoc meta blocks) = (xml_header ++) . showContent $ fb2_xml
  where
  fb2_xml = el "FictionBook" [desc, body]
  desc = el "description"
         [ el "title-info"
             ((booktitle meta) ++ (authors meta) ++ (docdate meta))
         , el "document-info"
           [ el "program-used" "pandoc"  -- FIXME: add version info
           ]
         ]
  booktitle :: Meta -> [Content]
  booktitle meta =
      let t = cMap toXml . docTitle $ meta
      in  if null $ t
          then []
          else [ el "book-title" t ]
  authors :: Meta -> [Content]
  authors meta = cMap author (docAuthors meta)
  author :: [Inline] -> [Content]
  author ss =
      let ws = words . cMap plain $ ss
          email = (el "email") `fmap` (take 1 $ filter ('@' `elem`) ws)
          ws' = filter ('@' `notElem`) ws
          names = case ws' of
                    (nickname:[]) -> [ el "nickname" nickname ]
                    (fname:lname:[]) -> [ el "first-name" fname
                                       , el "last-name" lname ]
                    (fname:rest) -> [ el "first-name" fname
                                   , el "middle-name" (concat . init $ rest)
                                   , el "last-name" (last rest) ]
                    ([]) -> []
      in  list $ el "author" (names ++ email)
  docdate :: Meta -> [Content]
  docdate meta =
      let ss = docDate meta
          d = cMap toXml ss
      in  if null d
          then []
          else [el "date" d]
  body = el "body" $ cMap blockToXml blocks

-- FIXME: section nesting constraint

-- Convert a block-level Pandoc's element to FictionBook XML representation.
blockToXml :: Block -> [Content]
blockToXml (Plain ss) = cMap toXml ss
blockToXml (Para ss) = [ el "p" (cMap toXml ss) ]
blockToXml (CodeBlock _ s) = [ el "p" (el "code" s) ]
blockToXml (RawBlock _ s) = [ el "p" (el "code" s) ]
blockToXml (BlockQuote bs) = [ el "cite" (cMap blockToXml bs) ]
blockToXml (OrderedList a bss) =
    let markers = orderedListMarkers a
        mkitem mrk bs = el "cite" $ [ txt mrk, txt " " ] ++ cMap blockToXml bs
    in  map (uncurry mkitem) (zip markers bss)
blockToXml (BulletList bss) =
    let mkitem bs = el "cite" $ [ txt "• " ] ++ cMap blockToXml bs
    in  map mkitem bss
blockToXml (DefinitionList defs) =
    cMap mkdef defs
    where
      mkdef (term, bss) =
          let def = cMap (cMap blockToXml) bss
          in  [ el "p" (wrap "strong" term), el "cite" def ]
blockToXml (Header n ss) = [ el "p" (el "strong" (cMap toXml ss)) ] -- FIXME
blockToXml HorizontalRule = [ el "empty-line" ()
                            , el "p" (txt (replicate 10 '—'))
                            , el "empty-line" () ]
blockToXml _ = []  -- FIXME: Table, Null

-- Convert a Pandoc's Inline element to FictionBook XML representation.
toXml :: Inline -> [Content]
toXml (Str s) = [txt s]
toXml (Emph ss) = list $ wrap "emphasis" ss
toXml (Strong ss) = list $ wrap "strong" ss
toXml (Strikeout ss) = list $ wrap "strikethrough" ss
toXml (Superscript ss) = list $ wrap "sup" ss
toXml (Subscript ss) = list $ wrap "sub" ss
toXml (SmallCaps ss) = cMap toXml $ bottomUp (map toUpper) ss
toXml (Quoted SingleQuote ss) = [txt "‘"] ++ cMap toXml ss ++ [txt "’"]
toXml (Quoted DoubleQuote ss) = [txt "“"] ++ cMap toXml ss ++ [txt "”"]
toXml (Cite _ ss) = cMap toXml ss  -- FIXME: support citation styles
toXml (Code _ s) = [el "code" s]
toXml Space = [txt " "]
toXml EmDash = [txt "—"]
toXml EnDash = [txt "–"]
toXml Apostrophe = [txt "’"]
toXml Ellipses = [txt "…"]
toXml LineBreak = [el "empty-line" ()]
toXml (Math InlineMath s) = [el "code" s] -- FIXME: generate formula images
toXml (Math DisplayMath s) = [el "p" (el "code" s)] -- FIXME: is <p> here OK?
toXml (RawInline _ s) = [el "code" s] -- FIXME: attempt to convert to plaintext
toXml (Link text (url,title)) = cMap toXml text -- FIXME: url in footnotes
toXml (Image alt (url,title)) = cMap toXml alt  -- FIXME: embed images
toXml (Note blocks) = [txt ""] -- FIXME: implement footnotes

-- Wrap all inlines with an XML tag (given its unqualified name).
wrap :: String -> [Inline] -> Content
wrap tagname inlines = el tagname $ cMap toXml inlines

-- Create a singleton list.
list :: a -> [a]
list = (:[])

-- Convert an 'Inline' to plaintext.
plain :: Inline -> String
plain (Str s) = s
plain (Emph ss) = concat (map plain ss)
plain (Strong ss) = concat (map plain ss)
plain (Strikeout ss) = concat (map plain ss)
plain (Superscript ss) = concat (map plain ss)
plain (Subscript ss) = concat (map plain ss)
plain (SmallCaps ss) = concat (map plain ss)
plain (Quoted qt ss) = concat (map plain ss)
plain (Cite _ ss) = concat (map plain ss)  -- FIXME
plain (Code _ s) = s
plain Space = " "
plain EmDash = "—"
plain EnDash = "–"
plain Apostrophe = "’"
plain Ellipses = "…"
plain LineBreak = "\n"
plain (Math mt s) = s
plain (RawInline _ s) = s
plain (Link text (url,title)) = concat (map plain text ++ [" <", url, ">"])
plain (Image alt _) = concat (map plain alt)
plain (Note blocks) = ""  -- FIXME

-- | Create an XML element.
el :: (Node t)
   => String   -- ^ unqualified element name
   -> t        -- ^ node contents
   -> Content  -- ^ XML content
el name cs = Elem $ unode name cs

-- | Create a plain-text XML content.
txt :: String -> Content
txt s = Text $ CData CDataText s Nothing

-- | Abbreviation for 'concatMap'.
cMap :: (a -> [b]) -> [a] -> [b]
cMap = concatMap