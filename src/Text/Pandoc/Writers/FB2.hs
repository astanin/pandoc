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

import Control.Monad.State
import Data.Char (toUpper, isSpace)
import Text.XML.Light

import Text.Pandoc.Definition
import Text.Pandoc.Shared (WriterOptions, orderedListMarkers)
import Text.Pandoc.Generic (bottomUp)

-- | Data to be written at the end of the document: (foot)notes, URLs, references, images.
data FBNotes = FBNotes
    { footnotes :: [ (Int, String, [Content]) ]  -- ^ #, ID, text
    } deriving (Show)

-- | FictionBook building monad.
type FBM = State FBNotes

newFB :: FBNotes
newFB = FBNotes { footnotes = [] }

-- | Produce an FB2 document from a 'Pandoc' document.
writeFB2 :: WriterOptions    -- ^ conversion options
         -> Pandoc           -- ^ document to convert
         -> String           -- ^ FictionBook2 document (not encoded yet)
writeFB2 _ (Pandoc meta blocks) = flip evalState newFB $ do
     desc <- description meta
     fp <- frontpage meta
     secs <- renderSections 1 blocks
     let body = el "body" $ fp ++ secs
     notes <- renderFootnotes
     let fb2_xml = el "FictionBook" (fb2_attrs, [desc, body] ++ notes)
     return $ xml_head ++ (showContent fb2_xml)
  where
  xml_head = "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
  fb2_attrs =
      let xmlns = "http://www.gribuser.ru/xml/fictionbook/2.0"
          xlink = "http://www.w3.org/1999/xlink"
      in  [ uattr "xmlns" xmlns
          , attr ("xmlns", "l") xlink ]
  --
  frontpage :: Meta -> FBM [Content]
  frontpage meta' = do
      t <- cMapM toXml . docTitle $ meta'
      return $
        [ el "title" (el "p" t)
        , el "annotation" (map (el "p" . cMap plain)
                           (docAuthors meta' ++ [docDate meta']))
        ]
  description :: Meta -> FBM Content
  description meta' = do
      bt <- booktitle meta'
      let as = authors meta'
      dd <- docdate meta'
      return $ el "description"
         [ el "title-info" (bt ++ as ++ dd)
         , el "document-info" [ el "program-used" "pandoc" ] -- FIXME: +version
         ]
  booktitle :: Meta -> FBM [Content]
  booktitle meta' = do
      t <- cMapM toXml . docTitle $ meta'
      return $ if null t
               then []
               else [ el "book-title" t ]
  authors :: Meta -> [Content]
  authors meta' = cMap author (docAuthors meta')
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
  docdate :: Meta -> FBM [Content]
  docdate meta' = do
      let ss = docDate meta'
      d <- cMapM toXml ss
      return $ if null d
               then []
               else [el "date" d]

-- | Divide the stream of blocks into sections and convert to XML representation.
renderSections :: Int -> [Block] -> FBM [Content]
renderSections level blocks = do
    let secs = splitSections level blocks
    mapM (renderSection level) secs

renderSection :: Int -> ([Inline], [Block]) -> FBM Content
renderSection level (ttl, bs) = do
    title <- if null ttl
            then return []
            else (list . el "title" . el "p") `liftM` cMapM toXml ttl
                 -- FIXME: only <p> and <empty-line> are allowed within <title>
    let subsecs = splitSections (level + 1) bs
    content <- if length subsecs == 1  -- if no subsections
              then cMapM blockToXml bs
              else renderSections (level + 1) bs
    return $ el "section" (title ++ content)

-- | Divide the stream of block elements into sections: [(title, blocks)].
splitSections :: Int -> [Block] -> [([Inline], [Block])]
splitSections level blocks = reverse $ revSplit (reverse blocks)
  where
  revSplit rblocks =
    let (lastsec, before) = break sameLevel rblocks
    in case before of
      ((Header _ inlines):prevblocks) ->
          (inlines, reverse lastsec) : revSplit prevblocks
      _ -> if null lastsec
           then []
           else [([], reverse lastsec)]
  sameLevel (Header n _) = n == level
  sameLevel _ = False

-- | Make another FictionBook body with footnotes.
renderFootnotes :: FBM [Content]
renderFootnotes = do
  fns <- footnotes `liftM` get
  if null fns
    then return []  -- no footnotes
    else return . list $
         el "body" ([uattr "name" "notes"], map renderFN (reverse fns))
  where
    renderFN (n, idstr, cs) =
        let fn_texts = (el "title" (el "p" (show n))) : cs
        in  el "section" ([uattr "id" idstr], fn_texts)

footnoteID :: Int -> String
footnoteID i = "n" ++ (show i)

linkID :: Int -> String
linkID i = "l" ++ (show i)

-- | Convert a block-level Pandoc's element to FictionBook XML representation.
blockToXml :: Block -> FBM [Content]
blockToXml (Plain ss) = cMapM toXml ss  -- FIXME: can lead to malformed FB2
blockToXml (Para ss) = liftM (list . el "p") $ cMapM toXml ss
blockToXml (CodeBlock _ s) = return . map (el "p" . el "code") . lines $ s
blockToXml (RawBlock _ s) = return [ el "p" (el "code" s) ]
blockToXml (BlockQuote bs) = liftM (list . el "cite") $ cMapM blockToXml bs
blockToXml (OrderedList a bss) =
    let markers = orderedListMarkers a
        mkitem mrk bs = do
          itemtext <- cMapM blockToXml bs
          return . el "cite" $ [ txt mrk, txt " " ] ++ itemtext
    in  mapM (uncurry mkitem) (zip markers bss)
blockToXml (BulletList bss) =
    let mkitem bs = do
          itemtext <- cMapM blockToXml bs
          return $ el "cite" $ [ txt "• " ] ++ itemtext
    in  mapM mkitem bss
blockToXml (DefinitionList defs) =
    cMapM mkdef defs
    where
      mkdef (term, bss) = do
          def <- cMapM (cMapM blockToXml) bss
          t <- wrap "strong" term
          return [ el "p" t, el "cite" def ]
blockToXml (Header _ _) = undefined  -- should never happen, see renderSections
blockToXml HorizontalRule = return
                            [ el "empty-line" ()
                            , el "p" (txt (replicate 10 '—'))
                            , el "empty-line" () ]
blockToXml (Table caption aligns _ headers rows) = do
    hd <- mkrow "th" headers aligns
    bd <- mapM (\r -> mkrow "td" r aligns) rows
    c <- return . el "emphasis" =<< cMapM toXml caption
    return [el "table" (hd : bd), el "p" c]
    where
      mkrow :: String -> [TableCell] -> [Alignment] -> FBM Content
      mkrow tag cells aligns' =
        (el "tr") `liftM` (mapM (mkcell tag) (zip cells aligns'))
      --
      mkcell :: String -> (TableCell, Alignment) -> FBM Content
      mkcell tag (cell, align) = do
        cblocks <- cMapM blockToXml cell
        return $ el tag ([align_attr align], cblocks)
      --
      align_attr a = Attr (QName "align" Nothing Nothing) (align_str a)
      align_str AlignLeft = "left"
      align_str AlignCenter = "center"
      align_str AlignRight = "right"
      align_str AlignDefault = "left"
blockToXml Null = return []

-- | Convert a Pandoc's Inline element to FictionBook XML representation.
toXml :: Inline -> FBM [Content]
toXml (Str s) = return [txt s]
toXml (Emph ss) = list `liftM` wrap "emphasis" ss
toXml (Strong ss) = list `liftM` wrap "strong" ss
toXml (Strikeout ss) = list `liftM` wrap "strikethrough" ss
toXml (Superscript ss) = list `liftM` wrap "sup" ss
toXml (Subscript ss) = list `liftM` wrap "sub" ss
toXml (SmallCaps ss) = cMapM toXml $ bottomUp (map toUpper) ss
toXml (Quoted SingleQuote ss) = do  -- FIXME: should be language-specific
  inner <- cMapM toXml ss
  return $ [txt "‘"] ++ inner ++ [txt "’"]
toXml (Quoted DoubleQuote ss) = do
  inner <- cMapM toXml ss
  return $ [txt "“"] ++ inner ++ [txt "”"]
toXml (Cite _ ss) = cMapM toXml ss  -- FIXME: support citation styles
toXml (Code _ s) = return [el "code" s]
toXml Space = return [txt " "]
toXml EmDash = return [txt "—"]
toXml EnDash = return [txt "–"]
toXml Apostrophe = return [txt "’"]
toXml Ellipses = return [txt "…"]
toXml LineBreak = return [el "empty-line" ()]
toXml (Math _ s) = return [el "code" s] -- FIXME: generate formula images
toXml (RawInline _ _) = return []  -- raw TeX and raw HTML are suppressed
toXml (Link text (url,ttl)) = do
  state <- get
  let fns = footnotes state
  let n = 1 + length fns
  let ln_id = linkID n
  let ln_ref = list . el "sup" . txt $ "[" ++ show n ++ "]"
  ln_text <- cMapM toXml text
  let ln_desc =
          let ttl' = dropWhile isSpace ttl
          in if null ttl'
             then list . el "p" $ el "code" url
             else list . el "p" $ [ txt (ttl' ++ ": "), el "code" url ]
  put state { footnotes = (n, ln_id, ln_desc) : fns }
  return $ ln_text ++
         [ el "a"
                  ( [ attr ("l","href") ('#':ln_id)
                    , uattr "type" "note" ]
                  , ln_ref) ]

toXml (Image alt (_,_)) = cMapM toXml alt  -- FIXME: embed images
toXml (Note bs) = do
  state <- get
  let fns = footnotes state
  let n = 1 + length fns
  let fn_id = footnoteID n
  fn_desc <- cMapM blockToXml bs
  put state { footnotes = (n, fn_id, fn_desc) : fns }
  let fn_ref = el "sup" . txt $ "[" ++ show n ++ "]"
  return . list $ el "a" ( [ attr ("l","href") ('#':fn_id)
                           , uattr "type" "note" ]
                         , fn_ref )

-- | Wrap all inlines with an XML tag (given its unqualified name).
wrap :: String -> [Inline] -> FBM Content
wrap tagname inlines = el tagname `liftM` cMapM toXml inlines

-- " Create a singleton list.
list :: a -> [a]
list = (:[])

-- | Convert an 'Inline' to plaintext.
plain :: Inline -> String
plain (Str s) = s
plain (Emph ss) = concat (map plain ss)
plain (Strong ss) = concat (map plain ss)
plain (Strikeout ss) = concat (map plain ss)
plain (Superscript ss) = concat (map plain ss)
plain (Subscript ss) = concat (map plain ss)
plain (SmallCaps ss) = concat (map plain ss)
plain (Quoted _ ss) = concat (map plain ss)
plain (Cite _ ss) = concat (map plain ss)  -- FIXME
plain (Code _ s) = s
plain Space = " "
plain EmDash = "—"
plain EnDash = "–"
plain Apostrophe = "’"
plain Ellipses = "…"
plain LineBreak = "\n"
plain (Math _ s) = s
plain (RawInline _ s) = s
plain (Link text (url,_)) = concat (map plain text ++ [" <", url, ">"])
plain (Image alt _) = concat (map plain alt)
plain (Note _) = ""  -- FIXME

-- | Create an XML element.
el :: (Node t)
   => String   -- ^ unqualified element name
   -> t        -- ^ node contents
   -> Content  -- ^ XML content
el name cs = Elem $ unode name cs

-- | Create a plain-text XML content.
txt :: String -> Content
txt s = Text $ CData CDataText s Nothing

-- | Create an XML attribute with an unqualified name.
uattr :: String -> String -> Text.XML.Light.Attr
uattr name val = Attr (QName name Nothing Nothing) val

-- | Create an XML attribute with a qualified name from given namespace.
attr :: (String, String) -> String -> Text.XML.Light.Attr
attr (ns, name) val = Attr (QName name Nothing (Just ns)) val

-- | Abbreviation for 'concatMap'.
cMap :: (a -> [b]) -> [a] -> [b]
cMap = concatMap

-- | Monadic equivalent of 'concatMap'.
cMapM :: (Monad m) => (a -> m [b]) -> [a] -> m [b]
cMapM f xs = concat `liftM` mapM f xs