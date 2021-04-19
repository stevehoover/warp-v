import { chakra, HTMLChakraProps } from '@chakra-ui/react'
import { HTMLMotionProps, motion, Variants } from 'framer-motion'
import * as React from 'react'

const navListMotion: Variants = {
  init: {
    opacity: 0,
    y: -4,
    display: 'none',
    transition: { duration: 0 },
  },
  enter: {
    opacity: 1,
    y: 0,
    display: 'block',
    transition: {
      duration: 0.15,
      staggerChildren: 0.1,
    },
  },
  exit: {
    opacity: 0,
    y: -4,
    transition: { duration: 0.1 },
    transitionEnd: {
      display: 'none',
    },
  },
}

type ListProps = HTMLChakraProps<'ul'> & HTMLMotionProps<'ul'>

export const MotionList = motion(chakra.li as React.ElementType<ListProps>)

export const NavListTransition = (props: ListProps) => (
  <MotionList opacity="0" initial="init" variants={navListMotion} {...props} />
)

const navItemMotion: Variants = {
  exit: {
    opacity: 0,
    y: 4,
  },
  enter: {
    opacity: 1,
    y: 0,
    transition: {
      duration: 0.3,
    },
  },
}

export const NavItemTransition = (props: HTMLMotionProps<'li'>) => (
  <motion.li variants={navItemMotion} {...props} />
)

